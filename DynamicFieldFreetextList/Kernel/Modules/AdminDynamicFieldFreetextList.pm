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

package Kernel::Modules::AdminDynamicFieldFreetextList;

use v5.24;
use strict;
use warnings;
use namespace::autoclean;
use utf8;

# OTOBO modules
use Kernel::System::VariableCheck qw(:all);
use Kernel::Language              qw(Translatable);

our $ObjectManagerDisabled = 1;

sub new {
    my ( $Type, %Param ) = @_;

    my $Self = bless {%Param}, $Type;

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    # Store last entity screen.
    $Kernel::OM->Get('Kernel::System::AuthSession')->UpdateSessionID(
        SessionID => $Self->{SessionID},
        Key       => 'LastScreenEntity',
        Value     => $Self->{RequestedURL},
    );

    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');

    if ( $Self->{Subaction} eq 'Add' ) {
        return $Self->_Add(%Param);
    }

    if ( $Self->{Subaction} eq 'AddAction' ) {
        $LayoutObject->ChallengeTokenCheck();
        return $Self->_AddAction(%Param);
    }

    if ( $Self->{Subaction} eq 'Change' ) {
        return $Self->_Change(%Param);
    }

    if ( $Self->{Subaction} eq 'ChangeAction' ) {
        $LayoutObject->ChallengeTokenCheck();
        return $Self->_ChangeAction(%Param);
    }

    return $LayoutObject->ErrorScreen(
        Message => Translatable('Undefined subaction.'),
    );
}

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

sub _Add {
    my ( $Self, %Param ) = @_;

    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $ParamObject  = $Kernel::OM->Get('Kernel::System::Web::Request');

    my %GetParam;

    # Support cloning an existing field
    my $CloneFieldID = $ParamObject->GetParam( Param => 'ID' );
    if ($CloneFieldID) {
        my $FieldConfig = $Kernel::OM->Get('Kernel::System::DynamicField')->DynamicFieldGet(
            ID => $CloneFieldID,
        );
        if ( IsHashRefWithData($FieldConfig) ) {
            for my $Key (qw(ObjectType FieldType Label Name ValidID)) {
                $GetParam{$Key} = $FieldConfig->{$Key};
            }
            if ( IsHashRefWithData( $FieldConfig->{Config} ) ) {
                $GetParam{PossibleValues} = $FieldConfig->{Config}{PossibleValues} // {};
            }
        }
        $GetParam{CloneFieldID} = $CloneFieldID;
    }

    for my $Needed (qw(ObjectType FieldType FieldOrder)) {
        $GetParam{$Needed} //= $ParamObject->GetParam( Param => $Needed );
        if ( !$GetParam{$Needed} ) {
            return $LayoutObject->ErrorScreen(
                Message => $LayoutObject->{LanguageObject}->Translate( 'Need %s', $Needed ),
            );
        }
    }

    for my $FilterParam (qw(ObjectTypeFilter NamespaceFilter)) {
        $GetParam{$FilterParam} = $ParamObject->GetParam( Param => $FilterParam );
    }

    my $ConfigObject   = $Kernel::OM->Get('Kernel::Config');
    my $ObjectTypeName = $ConfigObject->Get('DynamicFields::ObjectType')->{ $GetParam{ObjectType} }->{DisplayName} || '';
    my $FieldTypeName  = $ConfigObject->Get('DynamicFields::Driver')->{ $GetParam{FieldType} }->{DisplayName}      || '';

    my $Namespaces = $ConfigObject->Get('DynamicField::Namespaces');
    my $Namespace  = '';
    if ( IsArrayRefWithData($Namespaces) && $GetParam{NamespaceFilter} ) {
        $Namespace = ( grep { $_ eq $GetParam{NamespaceFilter} } $Namespaces->@* ) ? $GetParam{NamespaceFilter} : '';
    }

    return $Self->_ShowScreen(
        %Param,
        %GetParam,
        Mode           => 'Add',
        BreadcrumbText => $LayoutObject->{LanguageObject}->Translate(
            'Add %s field',
            $LayoutObject->{LanguageObject}->Translate($FieldTypeName),
        ),
        ObjectTypeName => $ObjectTypeName,
        FieldTypeName  => $FieldTypeName,
        Namespace      => $Namespace,
    );
}

sub _AddAction {
    my ( $Self, %Param ) = @_;

    my $ParamObject    = $Kernel::OM->Get('Kernel::System::Web::Request');
    my $LayoutObject   = $Kernel::OM->Get('Kernel::Output::HTML::Layout');

    my ( %Errors, %GetParam );

    for my $Needed (qw(Name Label FieldOrder)) {
        $GetParam{$Needed} = $ParamObject->GetParam( Param => $Needed );
        if ( !$GetParam{$Needed} ) {
            $Errors{ $Needed . 'ServerError' }        = 'ServerError';
            $Errors{ $Needed . 'ServerErrorMessage' } = Translatable('This field is required.');
        }
    }

    if ( $GetParam{FieldOrder} && $GetParam{FieldOrder} !~ m{\A\d+\z}xms ) {
        $Errors{FieldOrderServerError}        = 'ServerError';
        $Errors{FieldOrderServerErrorMessage} = Translatable('The field must be numeric.');
    }

    for my $ConfigParam (qw(ObjectType ObjectTypeName FieldType FieldTypeName ValidID Namespace)) {
        $GetParam{$ConfigParam} = $ParamObject->GetParam( Param => $ConfigParam );
    }

    for my $FilterParam (qw(ObjectTypeFilter NamespaceFilter)) {
        $GetParam{$FilterParam} = $ParamObject->GetParam( Param => $FilterParam );
    }

    # Collect the predefined list values submitted via the template
    $GetParam{PossibleValues} = $Self->_GetPossibleValues( ParamObject => $ParamObject );

    if ( $GetParam{Name} ) {
        if ( $GetParam{Name} !~ m{\A[a-zA-Z\d]+\z}xms ) {
            $Errors{NameServerError}        = 'ServerError';
            $Errors{NameServerErrorMessage} = Translatable('The field does not contain only ASCII letters and numbers.');
        }

        $GetParam{Name} = $GetParam{Namespace}
            ? $GetParam{Namespace} . '-' . $GetParam{Name}
            : $GetParam{Name};

        my $DynamicFieldObject = $Kernel::OM->Get('Kernel::System::DynamicField');
        my %DynamicFieldsList  = reverse %{
            $DynamicFieldObject->DynamicFieldList( Valid => 0, ResultType => 'HASH' )
        };

        if ( $DynamicFieldsList{ $GetParam{Name} } ) {
            $Errors{NameServerError}        = 'ServerError';
            $Errors{NameServerErrorMessage} = Translatable('There is another field with the same name.');
        }
    }

    if ( !$GetParam{ValidID} ) {
        return $LayoutObject->ErrorScreen( Message => Translatable('Need ValidID') );
    }

    if (%Errors) {
        return $Self->_ShowScreen( %Param, %Errors, %GetParam, Mode => 'Add' );
    }

    my $FieldID = $Kernel::OM->Get('Kernel::System::DynamicField')->DynamicFieldAdd(
        Name       => $GetParam{Name},
        Label      => $GetParam{Label},
        FieldOrder => $GetParam{FieldOrder},
        FieldType  => $GetParam{FieldType},
        ObjectType => $GetParam{ObjectType},
        Config     => { PossibleValues => $GetParam{PossibleValues} },
        ValidID    => $GetParam{ValidID},
        UserID     => $Self->{UserID},
    );

    if ( !$FieldID ) {
        return $LayoutObject->ErrorScreen( Message => Translatable('Could not create the new field') );
    }

    return $LayoutObject->Redirect(
        OP => $Self->_RedirectString( %GetParam, LayoutObject => $LayoutObject ),
    );
}

sub _Change {
    my ( $Self, %Param ) = @_;

    my $ParamObject  = $Kernel::OM->Get('Kernel::System::Web::Request');
    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');

    my %GetParam;
    for my $Needed (qw(ObjectType FieldType)) {
        $GetParam{$Needed} = $ParamObject->GetParam( Param => $Needed );
        if ( !$GetParam{$Needed} ) {
            return $LayoutObject->ErrorScreen(
                Message => $LayoutObject->{LanguageObject}->Translate( 'Need %s', $Needed ),
            );
        }
    }

    for my $FilterParam (qw(ObjectTypeFilter NamespaceFilter)) {
        $GetParam{$FilterParam} = $ParamObject->GetParam( Param => $FilterParam );
    }

    my $ConfigObject   = $Kernel::OM->Get('Kernel::Config');
    my $ObjectTypeName = $ConfigObject->Get('DynamicFields::ObjectType')->{ $GetParam{ObjectType} }->{DisplayName} || '';
    my $FieldTypeName  = $ConfigObject->Get('DynamicFields::Driver')->{ $GetParam{FieldType} }->{DisplayName}      || '';

    my $FieldID = $ParamObject->GetParam( Param => 'ID' );
    if ( !$FieldID ) {
        return $LayoutObject->ErrorScreen( Message => Translatable('Need ID') );
    }

    my $DynamicFieldData = $Kernel::OM->Get('Kernel::System::DynamicField')->DynamicFieldGet( ID => $FieldID );
    if ( !IsHashRefWithData($DynamicFieldData) ) {
        return $LayoutObject->ErrorScreen(
            Message => $LayoutObject->{LanguageObject}->Translate(
                'Could not get data for dynamic field %s', $FieldID
            ),
        );
    }

    my %Config;
    if ( IsHashRefWithData( $DynamicFieldData->{Config} ) ) {
        %Config = $DynamicFieldData->{Config}->%*;
    }

    return $Self->_ShowScreen(
        %Param,
        %GetParam,
        $DynamicFieldData->%*,
        %Config,
        ID             => $FieldID,
        Mode           => 'Change',
        BreadcrumbText => $LayoutObject->{LanguageObject}->Translate(
            'Change %s field',
            $LayoutObject->{LanguageObject}->Translate($FieldTypeName),
        ),
        ObjectTypeName => $ObjectTypeName,
        FieldTypeName  => $FieldTypeName,
    );
}

sub _ChangeAction {
    my ( $Self, %Param ) = @_;

    my $ParamObject  = $Kernel::OM->Get('Kernel::System::Web::Request');
    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');

    my ( %Errors, %GetParam );

    for my $Needed (qw(Name Label FieldOrder)) {
        $GetParam{$Needed} = $ParamObject->GetParam( Param => $Needed );
        if ( !$GetParam{$Needed} ) {
            $Errors{ $Needed . 'ServerError' }        = 'ServerError';
            $Errors{ $Needed . 'ServerErrorMessage' } = Translatable('This field is required.');
        }
    }

    my $FieldID = $ParamObject->GetParam( Param => 'ID' );
    if ( !$FieldID ) {
        return $LayoutObject->ErrorScreen( Message => Translatable('Need ID') );
    }

    my $DynamicFieldObject = $Kernel::OM->Get('Kernel::System::DynamicField');
    my $DynamicFieldData   = $DynamicFieldObject->DynamicFieldGet( ID => $FieldID );

    if ( !IsHashRefWithData($DynamicFieldData) ) {
        return $LayoutObject->ErrorScreen(
            Message => $LayoutObject->{LanguageObject}->Translate(
                'Could not get data for dynamic field %s', $FieldID
            ),
        );
    }

    if ( $GetParam{FieldOrder} && $GetParam{FieldOrder} !~ m{\A\d+\z}xms ) {
        $Errors{FieldOrderServerError}        = 'ServerError';
        $Errors{FieldOrderServerErrorMessage} = Translatable('The field must be numeric.');
    }

    for my $ConfigParam (qw(ObjectType ObjectTypeName FieldType FieldTypeName ValidID Namespace)) {
        $GetParam{$ConfigParam} = $ParamObject->GetParam( Param => $ConfigParam );
    }

    for my $FilterParam (qw(ObjectTypeFilter NamespaceFilter)) {
        $GetParam{$FilterParam} = $ParamObject->GetParam( Param => $FilterParam );
    }

    # Collect the predefined list values submitted via the template
    $GetParam{PossibleValues} = $Self->_GetPossibleValues( ParamObject => $ParamObject );

    if ( $GetParam{Name} ) {
        if ( $GetParam{Name} !~ m{\A[a-zA-Z\d]+\z}xms ) {
            $Errors{NameServerError}        = 'ServerError';
            $Errors{NameServerErrorMessage} = Translatable('The field does not contain only ASCII letters and numbers.');
        }

        $GetParam{Name} = $GetParam{Namespace}
            ? $GetParam{Namespace} . '-' . $GetParam{Name}
            : $GetParam{Name};

        my %DynamicFieldsList = reverse %{
            $DynamicFieldObject->DynamicFieldList( Valid => 0, ResultType => 'HASH' )
        };

        if (
            $DynamicFieldsList{ $GetParam{Name} }
            && $DynamicFieldsList{ $GetParam{Name} } ne $FieldID
            )
        {
            $Errors{NameServerError}        = 'ServerError';
            $Errors{NameServerErrorMessage} = Translatable('There is another field with the same name.');
        }

        if (
            $DynamicFieldData->{InternalField}
            && $DynamicFieldsList{ $GetParam{Name} } ne $FieldID
            )
        {
            $Errors{NameServerError}        = 'ServerError';
            $Errors{NameServerErrorMessage} = Translatable('The name for this field should not change.');
            $Param{InternalField}           = $DynamicFieldData->{InternalField};
        }
    }

    if ( !$GetParam{ValidID} ) {
        return $LayoutObject->ErrorScreen( Message => Translatable('Need ValidID') );
    }

    # Check SysConfig references
    my $UpdateEntity              = $ParamObject->GetParam( Param => 'UpdateEntity' ) || '';
    my $SysConfigObject           = $Kernel::OM->Get('Kernel::System::SysConfig');
    my %DynamicFieldOldData       = %{$DynamicFieldData};
    my @IsDynamicFieldInSysConfig = $SysConfigObject->ConfigurationEntityCheck(
        EntityType => 'DynamicField',
        EntityName => $DynamicFieldData->{Name},
    );

    if (@IsDynamicFieldInSysConfig) {
        if (
            $Kernel::OM->Get('Kernel::System::Valid')->ValidLookup( ValidID => $GetParam{ValidID} )
            ne 'valid'
            )
        {
            $Errors{ValidIDInvalid}         = 'ServerError';
            $Errors{ValidOptionServerError} = 'InSetting';
        }
        elsif ( $DynamicFieldData->{Name} ne $GetParam{Name} && !$UpdateEntity ) {
            $Errors{NameInvalid}              = 'ServerError';
            $Errors{InSettingNameServerError} = 1;
        }
    }

    if (%Errors) {
        return $Self->_ShowScreen( %Param, %Errors, %GetParam, ID => $FieldID, Mode => 'Change' );
    }

    my $UpdateSuccess = $DynamicFieldObject->DynamicFieldUpdate(
        ID         => $FieldID,
        Name       => $GetParam{Name},
        Label      => $GetParam{Label},
        FieldOrder => $GetParam{FieldOrder},
        FieldType  => $DynamicFieldData->{FieldType},
        ObjectType => $DynamicFieldData->{ObjectType},
        Config     => { PossibleValues => $GetParam{PossibleValues} },
        ValidID    => $GetParam{ValidID},
        UserID     => $Self->{UserID},
    );

    if ( !$UpdateSuccess ) {
        return $LayoutObject->ErrorScreen(
            Message => $LayoutObject->{LanguageObject}->Translate(
                'Could not update the field %s', $GetParam{Name}
            ),
        );
    }

    # Propagate name change to SysConfig if confirmed
    if (
        @IsDynamicFieldInSysConfig
        && $DynamicFieldOldData{Name} ne $GetParam{Name}
        && $UpdateEntity
        )
    {
        SETTING:
        for my $SettingName (@IsDynamicFieldInSysConfig) {
            my %Setting = $SysConfigObject->SettingGet( Name => $SettingName );
            next SETTING if !IsHashRefWithData( \%Setting );

            $Setting{EffectiveValue} =~ s/$DynamicFieldOldData{Name}/$GetParam{Name}/g;

            my $ExclusiveLockGUID = $SysConfigObject->SettingLock(
                Name   => $Setting{Name},
                Force  => 1,
                UserID => $Self->{UserID},
            );
            $Setting{ExclusiveLockGUID} = $ExclusiveLockGUID;

            $SysConfigObject->SettingUpdate( %Setting, UserID => $Self->{UserID} );
        }

        $SysConfigObject->ConfigurationDeploy(
            Comments      => 'DynamicField name change',
            DirtySettings => \@IsDynamicFieldInSysConfig,
            UserID        => $Self->{UserID},
            Force         => 1,
        );
    }

    my $FilterString = $Self->_FilterString( %GetParam, LayoutObject => $LayoutObject );

    if (
        defined $ParamObject->GetParam( Param => 'ContinueAfterSave' )
        && $ParamObject->GetParam( Param => 'ContinueAfterSave' ) eq '1'
        )
    {
        return $LayoutObject->Redirect(
            OP => "Action=$Self->{Action};Subaction=Change;ObjectType=$DynamicFieldData->{ObjectType};FieldType=$DynamicFieldData->{FieldType};ID=$FieldID$FilterString",
        );
    }

    return $LayoutObject->Redirect( OP => "Action=AdminDynamicField$FilterString" );
}

sub _ShowScreen {
    my ( $Self, %Param ) = @_;

    $Param{DisplayFieldName} = 'New';

    my $Namespace = $Param{Namespace};
    if ( $Param{Mode} eq 'Change' || ( $Param{Name} && !$Param{CloneFieldID} ) ) {
        $Param{ShowWarning} = 'ShowWarning';
        $Param{DisplayFieldName} = $Param{Name};

        if ( $Param{Name} =~ /(.*)-(.*)/ ) {
            $Namespace             = $1;
            $Param{PlainFieldName} = $2;
        }
        else {
            $Param{PlainFieldName} = $Param{Name};
        }
    }

    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');

    my $Output = join '',
        $LayoutObject->Header,
        $LayoutObject->NavigationBar;

    my $DynamicFieldObject = $Kernel::OM->Get('Kernel::System::DynamicField');

    my $DynamicFieldList = $DynamicFieldObject->DynamicFieldListGet( Valid => 0 );

    my @DynamicfieldOrderList;
    my %DynamicfieldNamesList;
    for my $Dynamicfield ( @{$DynamicFieldList} ) {
        push @DynamicfieldOrderList, $Dynamicfield->{FieldOrder};
        $DynamicfieldNamesList{ $Dynamicfield->{FieldOrder} } = $Dynamicfield->{Label};
    }

    if ( $Param{Mode} eq 'Add' ) {
        my $LastOrderNumber = $DynamicfieldOrderList[-1];
        $LastOrderNumber++;
        push @DynamicfieldOrderList, $LastOrderNumber;
    }

    my %OrderNamesList;
    my $CurrentlyText = $LayoutObject->{LanguageObject}->Translate('Currently') . ': ';
    for my $OrderNumber ( sort @DynamicfieldOrderList ) {
        $OrderNamesList{$OrderNumber} = $OrderNumber;
        if ( $DynamicfieldNamesList{$OrderNumber} && $OrderNumber ne $Param{FieldOrder} ) {
            $OrderNamesList{$OrderNumber}
                = $OrderNumber . ' - ' . $CurrentlyText . $DynamicfieldNamesList{$OrderNumber};
        }
    }

    my $DynamicFieldOrderStrg = $LayoutObject->BuildSelection(
        Data          => \%OrderNamesList,
        Name          => 'FieldOrder',
        SelectedValue => $Param{FieldOrder} || 1,
        PossibleNone  => 0,
        Translation   => 0,
        Sort          => 'NumericKey',
        Class         => 'Modernize W75pc Validate_Number',
    );

    my $NamespaceList = $Kernel::OM->Get('Kernel::Config')->Get('DynamicField::Namespaces');
    if ( IsArrayRefWithData($NamespaceList) ) {
        my $NamespaceStrg = $LayoutObject->BuildSelection(
            Data          => $NamespaceList,
            Name          => 'Namespace',
            SelectedValue => $Namespace || '',
            PossibleNone  => 1,
            Translation   => 0,
            Sort          => 'AlphanumericValue',
            Class         => 'Modernize W75pc',
        );
        $LayoutObject->Block(
            Name => 'DynamicFieldNamespace',
            Data => { NamespaceStrg => $NamespaceStrg },
        );
    }

    my %ValidList = $Kernel::OM->Get('Kernel::System::Valid')->ValidList();
    my $ValidityStrg = $LayoutObject->BuildSelection(
        Data         => \%ValidList,
        Name         => 'ValidID',
        SelectedID   => $Param{ValidID} || 1,
        PossibleNone => 0,
        Translation  => 1,
        Class        => 'Modernize W50pc',
    );

    # Prepare the list of predefined values for the template
    my $PossibleValues = $Param{PossibleValues} // {};
    my @PossibleValuesList;
    for my $Key ( sort keys %{$PossibleValues} ) {
        push @PossibleValuesList, { Value => $Key };
    }
    # Ensure at least one empty row for adding values
    push @PossibleValuesList, { Value => '' };

    # Render each existing value row
    my $ValueIndex = 0;
    for my $Row (@PossibleValuesList) {
        $LayoutObject->Block(
            Name => 'ValueRow',
            Data => {
                ValueIndex => $ValueIndex,
                Value      => $Row->{Value},
            },
        );
        $ValueIndex++;
    }

    my $ReadonlyInternalField = '';
    if ( $Param{InternalField} ) {
        $LayoutObject->Block( Name => 'InternalField', Data => {%Param} );
        $ReadonlyInternalField = 'readonly';
    }

    my $FieldID = $Kernel::OM->Get('Kernel::System::Web::Request')->GetParam( Param => 'ID' );
    if ($FieldID) {
        my $DynamicField     = $DynamicFieldObject->DynamicFieldGet( ID => $FieldID );
        my $DynamicFieldName = $DynamicField->{Name};

        my $SysConfigObject = $Kernel::OM->Get('Kernel::System::SysConfig');
        my $IsDirtyConfig   = 0;
        my @IsDirtyResult   = $SysConfigObject->ConfigurationDirtySettingsList();
        my %IsDirtyList     = map { $_ => 1 } @IsDirtyResult;

        my @IsDynamicFieldInSysConfig = $SysConfigObject->ConfigurationEntityCheck(
            EntityType => 'DynamicField',
            EntityName => $DynamicFieldName // '',
        );

        if (@IsDynamicFieldInSysConfig) {
            $LayoutObject->Block(
                Name => 'DynamicFieldInSysConfig',
                Data => { OldName => $DynamicFieldName },
            );
            for my $SettingName (@IsDynamicFieldInSysConfig) {
                $LayoutObject->Block(
                    Name => 'DynamicFieldInSysConfigRow',
                    Data => { SettingName => $SettingName },
                );
                $IsDirtyConfig = 1 if $IsDirtyList{$SettingName};
            }
        }

        $LayoutObject->Block( Name => 'DynamicFieldInSysConfigDirty' ) if $IsDirtyConfig;
    }

    my $FilterStrg = $Self->_FilterString( %Param, LayoutObject => $LayoutObject );

    $Output .= $LayoutObject->Output(
        TemplateFile => 'AdminDynamicFieldFreetextList',
        Data         => {
            %Param,
            ValidityStrg          => $ValidityStrg,
            DynamicFieldOrderStrg => $DynamicFieldOrderStrg,
            ReadonlyInternalField => $ReadonlyInternalField,
            FilterStrg            => $FilterStrg,
            ValueCount            => $ValueIndex,
        },
    );

    $Output .= $LayoutObject->Footer;

    return $Output;
}

# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

# Reads all PossibleValues_<n> form params and returns a hash ref.
sub _GetPossibleValues {
    my ( $Self, %Param ) = @_;

    my $ParamObject = $Param{ParamObject};
    my %Values;

    my $Index = 0;
    while (1) {
        my $Value = $ParamObject->GetParam( Param => "PossibleValues_$Index" );
        last if !defined $Value;
        $Value =~ s/^\s+|\s+$//g;    # trim whitespace
        $Values{$Value} = $Value if length $Value;
        $Index++;
    }

    return \%Values;
}

# Builds the filter query string for redirects.
sub _FilterString {
    my ( $Self, %Param ) = @_;

    my $LayoutObject = delete $Param{LayoutObject};
    my $FilterStrg   = '';

    if ( IsStringWithData( $Param{ObjectTypeFilter} ) ) {
        $FilterStrg .= ';ObjectTypeFilter=' . $LayoutObject->Output(
            Template => '[% Data.Filter | uri %]',
            Data     => { Filter => $Param{ObjectTypeFilter} },
        );
    }

    if ( IsStringWithData( $Param{NamespaceFilter} ) ) {
        $FilterStrg .= ';NamespaceFilter=' . $LayoutObject->Output(
            Template => '[% Data.Filter | uri %]',
            Data     => { Filter => $Param{NamespaceFilter} },
        );
    }

    return $FilterStrg;
}

# Builds the redirect OP for AddAction.
sub _RedirectString {
    my ( $Self, %Param ) = @_;

    my $LayoutObject = delete $Param{LayoutObject};
    my $FilterStrg   = $Self->_FilterString( %Param, LayoutObject => $LayoutObject );

    return "Action=AdminDynamicField$FilterStrg";
}

1;
