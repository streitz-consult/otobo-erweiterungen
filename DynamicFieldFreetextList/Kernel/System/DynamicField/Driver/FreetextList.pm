# --
# OTOBO is a web-based ticketing system for service organisations.
# --
# Copyright (C) 2019-2025 Rother OSS GmbH, https://otobo.io/
# --
# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, either version 3 of the License, or (at your option) any later version.
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <https://www.gnu.org/licenses/>.
# --

package Kernel::System::DynamicField::Driver::FreetextList;

use v5.24;
use strict;
use warnings;
use namespace::autoclean;
use utf8;

use parent qw(Kernel::System::DynamicField::Driver::BaseText);

# OTOBO modules
use Kernel::Language              qw(Translatable);
use Kernel::System::VariableCheck qw(:all);

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::Output::HTML::Layout',
    'Kernel::System::DynamicField',
    'Kernel::System::DynamicFieldValue',
    'Kernel::System::Log',
    'Kernel::System::Web::Request',
);

=head1 NAME

Kernel::System::DynamicField::Driver::FreetextList

=head1 DESCRIPTION

DynamicFields FreetextList Driver delegate.

This dynamic field type combines a free-text input with a predefined list of values.
Users can either select a value from the list or enter any custom text.
When a new value is entered that is not yet in the list, it gets automatically
added to the field's configuration so it is available for future selections.

=head1 PUBLIC INTERFACE

This module implements the public interface of L<Kernel::System::DynamicField::Backend>.
Please look there for a detailed reference of the functions.

=head2 new()

Usually, you want to create an instance of this by using
Kernel::System::DynamicField::Backend->new();

=cut

sub new {
    my ($Type) = @_;

    my $Self = $Type->SUPER::new;

    # Set field-type-specific behaviors
    $Self->{Behaviors}->{IsSortable}       //= 1;
    $Self->{Behaviors}->{IsStatsCondition} //= 1;
    $Self->{Behaviors}->{IsSetCapable}     //= 1;

    return $Self;
}

=head2 ValueSet()

Stores the value and, if the value is not yet in the predefined list,
automatically extends that list with the new value.

=cut

sub ValueSet {
    my ( $Self, %Param ) = @_;

    # Store the submitted value directly via DynamicFieldValue (stable across all OTOBO versions).
    my $Success = $Kernel::OM->Get('Kernel::System::DynamicFieldValue')->ValueSet(
        FieldID  => $Param{DynamicFieldConfig}->{ID},
        ObjectID => $Param{ObjectID},
        Value    => [ { ValueText => $Param{Value} } ],
        UserID   => $Param{UserID},
    );

    return if !$Success;

    # Extract the actual value — it may come as an array ref or scalar
    my $Value = $Param{Value};
    if ( IsArrayRefWithData($Value) ) {
        $Value = $Value->[0];
    }

    # Only auto-extend the list for non-empty scalar values
    return $Success if !defined $Value || ref $Value || $Value eq '';

    # Trim whitespace
    $Value =~ s/^\s+|\s+$//g;
    return $Success if $Value eq '';

    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

    $LogObject->Log(
        Priority => 'debug',
        Message  => "FreetextList: ValueSet called with Value='$Value', FieldID=$Param{DynamicFieldConfig}->{ID}",
    );

    # The DynamicFieldConfig passed to ValueSet may be incomplete.
    # Reload the full config to ensure all fields are present and up-to-date from DB.
    my $FullFieldConfig = $Kernel::OM->Get('Kernel::System::DynamicField')->DynamicFieldGet(
        ID => $Param{DynamicFieldConfig}->{ID},
    );

    if ( !IsHashRefWithData($FullFieldConfig) ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "FreetextList: Could not reload field config for ID $Param{DynamicFieldConfig}->{ID}",
        );
        return $Success;
    }

    # Now get the PossibleValues from the FRESHLY loaded config (not from Param)
    my $PossibleValues = $FullFieldConfig->{Config}{PossibleValues} // {};

    # Validate PossibleValues is actually a hash reference
    if ( !IsHashRefWithData($PossibleValues) ) {
        $LogObject->Log(
            Priority => 'warn',
            Message  => "FreetextList: PossibleValues is not a valid HASH! Current type: "
                . ref($PossibleValues)
                . ", Value: " . ( defined $PossibleValues ? $PossibleValues : 'undef' ),
        );
        $PossibleValues = {};
    }

    $LogObject->Log(
        Priority => 'debug',
        Message  => "FreetextList: Current PossibleValues from DB (count=" 
            . scalar( keys %{$PossibleValues} ) . "): " 
            . join(', ', sort keys %{$PossibleValues}),
    );

    # Nothing to do if the value is already in the configured list
    if ( exists $PossibleValues->{$Value} ) {
        $LogObject->Log(
            Priority => 'debug',
            Message  => "FreetextList: Value '$Value' already exists in PossibleValues, no update needed",
        );
        return $Success;
    }

    $LogObject->Log(
        Priority => 'debug',
        Message  => "FreetextList: Auto-extending PossibleValues with new value '$Value'",
    );

    # Extend the list so the new value is available as autocomplete suggestion next time.
    # Important: copy all existing values to prevent data loss.
    my %UpdatedValues = %{$PossibleValues};
    $UpdatedValues{$Value} = $Value;

    $LogObject->Log(
        Priority => 'debug',
        Message  => "FreetextList: Updated PossibleValues will be: " . join(', ', sort keys %UpdatedValues),
    );

    # Build the updated config: We must use deep copy to preserve complex config structures
    # Don't use shallow copy here as it can corrupt nested references
    my %UpdatedConfig = ();
    
    # Copy all existing config values first
    for my $ConfigKey ( keys %{ $FullFieldConfig->{Config} } ) {
        if ( $ConfigKey eq 'PossibleValues' ) {
            # Don't copy PossibleValues yet, we'll set it explicitly below
            next;
        }
        
        # For non-reference values, copy directly
        if ( !ref $FullFieldConfig->{Config}{$ConfigKey} ) {
            $UpdatedConfig{$ConfigKey} = $FullFieldConfig->{Config}{$ConfigKey};
        }
        # For hash references, make a proper copy
        elsif ( ref $FullFieldConfig->{Config}{$ConfigKey} eq 'HASH' ) {
            $UpdatedConfig{$ConfigKey} = { %{ $FullFieldConfig->{Config}{$ConfigKey} } };
        }
        # For array references, make a proper copy
        elsif ( ref $FullFieldConfig->{Config}{$ConfigKey} eq 'ARRAY' ) {
            $UpdatedConfig{$ConfigKey} = [ @{ $FullFieldConfig->{Config}{$ConfigKey} } ];
        }
        # For other reference types, copy the reference as-is
        else {
            $UpdatedConfig{$ConfigKey} = $FullFieldConfig->{Config}{$ConfigKey};
        }
    }
    
    # Now set the updated PossibleValues
    $UpdatedConfig{PossibleValues} = \%UpdatedValues;

    # Now perform the update with the complete config
    my $UpdateSuccess = eval {
        $Kernel::OM->Get('Kernel::System::DynamicField')->DynamicFieldUpdate(
            ID         => $FullFieldConfig->{ID},
            Name       => $FullFieldConfig->{Name},
            Label      => $FullFieldConfig->{Label},
            FieldOrder => $FullFieldConfig->{FieldOrder},
            FieldType  => $FullFieldConfig->{FieldType},
            ObjectType => $FullFieldConfig->{ObjectType},
            ValidID    => $FullFieldConfig->{ValidID},
            Config     => \%UpdatedConfig,
            UserID     => $Param{UserID},
        );
    };

    if ( my $Error = $@ ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "FreetextList: Exception during DynamicFieldUpdate for value '$Value': $Error",
        );
        return $Success;
    }

    if ( !$UpdateSuccess ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => "FreetextList: DynamicFieldUpdate returned false for value '$Value' (ID: $FullFieldConfig->{ID})",
        );
    }
    else {
        $LogObject->Log(
            Priority => 'debug',
            Message  => "FreetextList: Successfully added value '$Value' to PossibleValues",
        );

        # Clear the DynamicField cache so EditFieldRender and other methods
        # pick up the updated PossibleValues list immediately.
        # We need to delete multiple cache keys because different parts of the system
        # may cache the DynamicField config under different keys.
        my $CacheObj = $Kernel::OM->Get('Kernel::System::Cache');
        
        # Delete ID-based cache (primary cache key)
        $CacheObj->Delete(
            Type => 'DynamicField',
            Key  => "DynamicFieldGet::ID::$FullFieldConfig->{ID}",
        );
        
        # Delete Name-based cache (secondary cache key)
        $CacheObj->Delete(
            Type => 'DynamicField',
            Key  => "DynamicFieldGet::Name::$FullFieldConfig->{Name}",
        );
        
        # Delete full DynamicFieldList cache
        $CacheObj->Delete(
            Type => 'DynamicFieldList',
            Key  => 'DynamicFieldList',
        );
        
        # Delete Backend cache (used by DynamicField::Backend)
        $CacheObj->Delete(
            Type => 'DynamicField',
            Key  => 'DynamicFieldListGet',
        );
        
        # Also delete the list caches for different object types and valid combinations
        for my $ObjectType (qw(Article ITSMConfigItem Ticket)) {
            for my $Valid (0, 1) {
                $CacheObj->Delete(
                    Type => 'DynamicFieldList',
                    Key  => "DynamicFieldListGet::Valid::${Valid}::ObjectType::${ObjectType}",
                );
            }
        }

        $LogObject->Log(
            Priority => 'debug',
            Message  => "FreetextList: Cleared all relevant caches for ID $FullFieldConfig->{ID}",
        );
    }

    return $Success;
}

=head2 PossibleValuesGet()

Returns the list of predefined values for this field.
Called by the OTOBO Backend layer before rendering, so the result is used
everywhere possible values are needed (datalist, stats, search, …).

=cut

sub PossibleValuesGet {
    my ( $Self, %Param ) = @_;

    # If a caller-supplied filter was explicitly provided, honour it.
    if ( IsHashRefWithData( $Param{PossibleValuesFilter} ) ) {
        return $Param{PossibleValuesFilter};
    }

    # IMPORTANT: We must ensure we get fresh data from the database, not cached data.
    # When ValueSet() adds new values, the cache is invalidated, but the DynamicFieldConfig
    # parameter passed to us might still be stale. So we reload from DB if we have an ID.
    
    my $PossibleValues = $Param{DynamicFieldConfig}->{Config}{PossibleValues} // {};
    
    # If we have a field ID, reload the config from DB to ensure we get the latest values
    if ( $Param{DynamicFieldConfig}->{ID} ) {
        my $LogObject = $Kernel::OM->Get('Kernel::System::Log');
        
        $LogObject->Log(
            Priority => 'debug',
            Message  => "FreetextList::PossibleValuesGet: Reloading fresh config from DB for field ID "
                . $Param{DynamicFieldConfig}->{ID}
                . " (initial count: " . scalar( keys %{$PossibleValues} ) . ")",
        );
        
        my $FreshConfig = $Kernel::OM->Get('Kernel::System::DynamicField')->DynamicFieldGet(
            ID => $Param{DynamicFieldConfig}->{ID},
        );
        
        if ( IsHashRefWithData($FreshConfig) && IsHashRefWithData( $FreshConfig->{Config} ) ) {
            my $FreshPossibleValues = $FreshConfig->{Config}{PossibleValues} // {};
            
            if ( IsHashRefWithData($FreshPossibleValues) ) {
                $LogObject->Log(
                    Priority => 'debug',
                    Message  => "FreetextList::PossibleValuesGet: Fresh config loaded, count: "
                        . scalar( keys %{$FreshPossibleValues} )
                        . ", Values: " . join(', ', sort keys %{$FreshPossibleValues}),
                );
                
                return $FreshPossibleValues;
            }
            else {
                $LogObject->Log(
                    Priority => 'warn',
                    Message  => "FreetextList::PossibleValuesGet: Fresh config PossibleValues is not a HASH!",
                );
            }
        }
        else {
            $LogObject->Log(
                Priority => 'warn',
                Message  => "FreetextList::PossibleValuesGet: Could not load fresh config for ID "
                    . $Param{DynamicFieldConfig}->{ID},
            );
        }
    }

    return $PossibleValues;
}

=head2 EditFieldRender()

Renders an HTML combobox: a text input backed by a <datalist> element that
lists all predefined values. Browsers show the datalist as autocomplete
suggestions while still allowing arbitrary free-text input.

=cut

sub EditFieldRender {
    my ( $Self, %Param ) = @_;

    my $FieldName  = 'DynamicField_' . $Param{DynamicFieldConfig}->{Name};
    my $DatalistID = $FieldName . '_Datalist';

    # Current value: prefer submitted param over stored value
    my $Value = '';
    if ( defined $Param{Value} && !ref $Param{Value} ) {
        $Value = $Param{Value};
    }

    my $Mandatory   = $Param{Mandatory}   ? 1 : 0;
    my $ServerError = $Param{ServerError} ? 'ServerError' : '';

    # Use PossibleValuesGet so the OTOBO Backend layer's normalisation and any
    # configured PossibleValuesFilter are both respected.
    my $PossibleValues  = $Self->PossibleValuesGet(%Param);
    
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');
    $LogObject->Log(
        Priority => 'debug',
        Message  => "FreetextList::EditFieldRender: Field="
            . $Param{DynamicFieldConfig}->{Name}
            . " has " . scalar( keys %{$PossibleValues} ) . " possible values: "
            . join(', ', sort keys %{$PossibleValues}),
    );
    
    my $DatalistOptions = '';
    for my $Key ( sort keys %{$PossibleValues} ) {
        my $EscapedKey = $Param{LayoutObject}->Ascii2Html( Text => $Key );
        $DatalistOptions .= "    <option value=\"$EscapedKey\">\n";
    }

    my $ValidateClass = $Mandatory ? ' Validate_Required' : '';
    my $EscapedValue  = $Param{LayoutObject}->Ascii2Html( Text => $Value );

    # Build raw HTML — no inline TT2 so we avoid the Output(Template=>) file-lookup issue.
    # Translations are resolved via LanguageObject directly.
    my $FieldHTML = qq{<input type="text" id="$FieldName" name="$FieldName" list="$DatalistID" }
        . qq{class="W50pc$ValidateClass $ServerError" value="$EscapedValue" autocomplete="off" />\n}
        . qq{<datalist id="$DatalistID">\n$DatalistOptions</datalist>\n};

    if ($Mandatory) {
        my $RequiredMsg = $Param{LayoutObject}->Ascii2Html(
            Text => $Param{LayoutObject}->{LanguageObject}->Translate('This field is required.'),
        );
        $FieldHTML .= qq{<div id="${FieldName}Error" class="TooltipErrorMessage"><p>$RequiredMsg</p></div>\n};
        $FieldHTML .= qq{<div id="${FieldName}ServerError" class="TooltipErrorMessage"><p>$RequiredMsg</p></div>\n};
    }

    my $Label = $Self->EditLabelRender(
        %Param,
        DynamicFieldConfig => $Param{DynamicFieldConfig},
        Mandatory          => $Mandatory,
        FieldName          => $FieldName,
    );

    return {
        Field => $FieldHTML,
        Label => $Label,
    };
}

=head2 EditFieldValueGet()

Returns the submitted text value for this field.

=cut

sub EditFieldValueGet {
    my ( $Self, %Param ) = @_;

    # ParamObject is not always provided (e.g. GenericAgent template context)
    return if !$Param{ParamObject};

    my $FieldName = 'DynamicField_' . $Param{DynamicFieldConfig}->{Name};

    return $Param{ParamObject}->GetParam( Param => $FieldName );
}

=head2 EditFieldValueValidate()

Validates the submitted value. Only checks for mandatory compliance;
any text (including values outside the predefined list) is accepted.

=cut

sub EditFieldValueValidate {
    my ( $Self, %Param ) = @_;

    my $Value = $Self->EditFieldValueGet(%Param);

    if ( $Param{Mandatory} && ( !defined $Value || $Value eq '' ) ) {
        return {
            ServerError  => 1,
            ErrorMessage => Translatable('This field is required.'),
        };
    }

    return { ServerError => 0 };
}

=head2 DisplayValueRender()

Returns the stored value as plain text / HTML for display.

=cut

sub DisplayValueRender {
    my ( $Self, %Param ) = @_;

    my $Value = defined $Param{Value} ? $Param{Value} : '';

    # HTMLOutput defaults to 1 (show HTML-escaped value)
    if ( $Param{HTMLOutput} // 1 ) {
        $Value = $Param{LayoutObject}->Ascii2Html(
            Text => $Value,
            Max  => $Param{ValueMaxChars} || '',
        );
    }
    else {
        if ( $Param{ValueMaxChars} && length $Value > $Param{ValueMaxChars} ) {
            $Value = substr( $Value, 0, $Param{ValueMaxChars} ) . '...';
        }
    }

    return {
        Value => $Value,
        Title => $Value,
        Link  => undef,
    };
}

=head2 SearchFieldRender()

Renders a plain text input for use in the search/filter form.

=cut

sub SearchFieldRender {
    my ( $Self, %Param ) = @_;

    my $FieldName  = 'Search_DynamicField_' . $Param{DynamicFieldConfig}->{Name};
    my $FieldLabel = $Param{DynamicFieldConfig}->{Label};

    my $Value = $Param{DefaultValue} // '';
    if ( $Param{Profile} ) {
        $Value = $Param{Profile}->{$FieldName} // '';
    }

    my $EscapedValue = $Param{LayoutObject}->Ascii2Html( Text => $Value );

    my $HTMLString = qq{<input type="text" id="$FieldName" name="$FieldName" value="$EscapedValue" class="W50pc" />\n};

    my $Label = $Self->EditLabelRender(
        %Param,
        DynamicFieldConfig => $Param{DynamicFieldConfig},
        FieldName          => $FieldName,
    );

    return {
        Field => $HTMLString,
        Label => $Label,
    };
}

=head2 SearchFieldValueGet()

Returns the search value submitted via the search form.

=cut

sub SearchFieldValueGet {
    my ( $Self, %Param ) = @_;

    my $FieldName = 'Search_DynamicField_' . $Param{DynamicFieldConfig}->{Name};

    if ( IsHashRefWithData( $Param{Profile} ) ) {
        return $Param{Profile}->{$FieldName};
    }

    return if !$Param{ParamObject};
    return $Param{ParamObject}->GetParam( Param => $FieldName );
}

=head2 SearchFieldParameterBuild()

Translates the search-field value into a backend search parameter hash.

=cut

sub SearchFieldParameterBuild {
    my ( $Self, %Param ) = @_;

    my $Value = $Self->SearchFieldValueGet(%Param);

    return {} if !defined $Value || $Value eq '';

    return {
        Operator => 'Like',
        Value    => '*' . $Value . '*',
    };
}

=head2 StatsFieldParameterBuild()

Returns parameters suitable for use in statistics.

=cut

sub StatsFieldParameterBuild {
    my ( $Self, %Param ) = @_;

    my $PossibleValues = $Param{DynamicFieldConfig}->{Config}->{PossibleValues} // {};

    return {
        Name             => $Param{DynamicFieldConfig}->{Label},
        Element          => 'DynamicField_' . $Param{DynamicFieldConfig}->{Name},
        Block            => 'InputField',
        Values           => $PossibleValues,
        SelectedValues   => [],
        TranslatableValues => 0,
    };
}

=head2 ReadableValueRender()

Returns a simple string representation of the value for e.g. notifications.

=cut

sub ReadableValueRender {
    my ( $Self, %Param ) = @_;

    my $Value = defined $Param{Value} ? $Param{Value} : '';

    if ( $Param{ValueMaxChars} && length $Value > $Param{ValueMaxChars} ) {
        $Value = substr( $Value, 0, $Param{ValueMaxChars} ) . '...';
    }

    return {
        Value => $Value,
        Title => $Value,
    };
}

=head2 TemplateValueTypeGet()

Returns 'SCALAR' because a single text string is stored per object.

=cut

sub TemplateValueTypeGet {
    my ( $Self, %Param ) = @_;

    my $FieldName = 'DynamicField_' . $Param{DynamicFieldConfig}->{Name};

    if ( $Param{FieldType} eq 'Edit' ) {
        return { $FieldName => 'SCALAR' };
    }

    return { $FieldName => 'SCALAR' };
}

=head2 ObjectMatch()

Returns 1 if the stored value matches the given comparison value.

=cut

sub ObjectMatch {
    my ( $Self, %Param ) = @_;

    my $FieldName = 'DynamicField_' . $Param{DynamicFieldConfig}->{Name};

    return 0 if !defined $Param{ObjectAttributes}->{$FieldName};

    return $Param{ObjectAttributes}->{$FieldName} eq $Param{Value} ? 1 : 0;
}

=head2 ValueLookup()

Looks up the display label for a stored key value.
For FreetextList, key and label are identical.

=cut

sub ValueLookup {
    my ( $Self, %Param ) = @_;

    return $Param{Key} // '';
}

1;
