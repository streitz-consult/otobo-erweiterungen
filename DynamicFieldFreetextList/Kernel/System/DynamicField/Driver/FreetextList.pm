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

    # Delegate actual DB storage to the base class
    my $Success = $Self->SUPER::ValueSet(%Param);
    return $Success if !$Success;

    # Only add to list when a non-empty scalar value was submitted
    my $Value = $Param{Value};
    return $Success if !defined $Value || ref $Value;
    return $Success if $Value eq '';

    my $DynamicFieldConfig = $Param{DynamicFieldConfig};
    my $PossibleValues     = $DynamicFieldConfig->{Config}{PossibleValues} // {};

    # Nothing to do if the value is already in the list
    return $Success if exists $PossibleValues->{$Value};

    # Extend the list with the new value (key == label for free-text items)
    my %UpdatedValues = ( %{$PossibleValues}, $Value => $Value );

    my $DynamicFieldObject = $Kernel::OM->Get('Kernel::System::DynamicField');

    $DynamicFieldObject->DynamicFieldUpdate(
        %{$DynamicFieldConfig},
        Config => {
            %{ $DynamicFieldConfig->{Config} },
            PossibleValues => \%UpdatedValues,
        },
        UserID => $Param{UserID},
    );

    return $Success;
}

=head2 EditFieldRender()

Renders an HTML combobox: a text input backed by a <datalist> element that
lists all predefined values. Browsers show the datalist as autocomplete
suggestions while still allowing arbitrary free-text input.

=cut

sub EditFieldRender {
    my ( $Self, %Param ) = @_;

    my $FieldConfig = $Param{DynamicFieldConfig}->{Config};
    my $FieldName   = 'DynamicField_' . $Param{DynamicFieldConfig}->{Name};
    my $FieldID     = $FieldName;
    my $DatalistID  = $FieldName . '_Datalist';

    # Determine current value - prefer submitted over stored
    my $Value = '';
    if ( defined $Param{Value} ) {
        $Value = $Param{Value};
    }

    my $Mandatory   = $Param{Mandatory}   ? '1' : '0';
    my $ServerError = $Param{ServerError} ? 'ServerError' : '';

    # Build <option> tags for the datalist from the configured list
    my $PossibleValues = $FieldConfig->{PossibleValues} // {};
    my $DatalistOptions = '';
    for my $Key ( sort keys %{$PossibleValues} ) {
        my $EscapedKey = $Param{LayoutObject}->Ascii2Html( Text => $Key );
        $DatalistOptions .= "            <option value=\"$EscapedKey\">\n";
    }

    my $ValidateClass = $Mandatory ? ' Validate_Required' : '';
    my $EscapedValue  = $Param{LayoutObject}->Ascii2Html( Text => $Value );

    my $HTMLString = <<"HTML";
        <input type="text"
               id="$FieldID"
               name="$FieldName"
               list="$DatalistID"
               class="W50pc$ValidateClass $ServerError"
               value="$EscapedValue"
               autocomplete="off" />
        <datalist id="$DatalistID">
$DatalistOptions        </datalist>
HTML

    if ($Mandatory) {
        $HTMLString .= <<"HTML";
        <div id="${FieldID}Error" class="TooltipErrorMessage">
            <p>[% Translate("This field is required.") | html %]</p>
        </div>
        <div id="${FieldID}ServerError" class="TooltipErrorMessage">
            <p>[% Translate("This field is required.") | html %]</p>
        </div>
HTML
    }

    # Render via Layout->Output so TT blocks are processed
    my $Field = $Param{LayoutObject}->Output(
        Template => $HTMLString,
    );

    my $Label = $Self->EditLabelRender(
        %Param,
        DynamicFieldConfig => $Param{DynamicFieldConfig},
        Mandatory          => $Mandatory,
        FieldName          => $FieldName,
    );

    return {
        Field => $Field,
        Label => $Label,
    };
}

=head2 EditFieldValueGet()

Returns the submitted text value for this field.

=cut

sub EditFieldValueGet {
    my ( $Self, %Param ) = @_;

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

    if ( $Param{HTMLOutput} ) {
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

    my $HTMLString = <<"HTML";
        <input type="text" id="$FieldName" name="$FieldName" value="$EscapedValue" class="W50pc" />
HTML

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

    if ( $Param{Type} eq 'CustomerInterface' ) {
        $FieldName = 'Search_DynamicField_' . $Param{DynamicFieldConfig}->{Name};
    }

    if ( $Param{Profile} ) {
        return $Param{Profile}->{$FieldName};
    }

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
