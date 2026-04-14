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

package Kernel::Language::de_OTOBODynamicFieldFreetextList;

use strict;
use warnings;
use utf8;

sub Data {
    my $Self = shift;

    # Template: AdminDynamicFieldFreetextList
    $Self->{Translation}->{'Freetext List'}         = 'Freitextfeld mit Liste';
    $Self->{Translation}->{'Field Settings'}        = 'Feldeinstellungen';
    $Self->{Translation}->{'Add value'}             = 'Wert hinzufügen';
    $Self->{Translation}->{'Remove value'}          = 'Wert entfernen';
    $Self->{Translation}->{'Enter a value'}         = 'Wert eingeben';
    $Self->{Translation}->{'Define the list of values that users can choose from. Users may also type any custom value not listed here – it will be added automatically.'} =
        'Definieren Sie die Liste der Werte, aus denen Benutzer auswählen können. Benutzer können auch beliebige eigene Werte eingeben – diese werden automatisch zur Liste hinzugefügt.';

    # Perl Module: Kernel/Modules/AdminDynamicFieldFreetextList.pm
    $Self->{Translation}->{'Could not create the new field'}          = 'Das neue Feld konnte nicht erstellt werden.';
    $Self->{Translation}->{'Could not update the field %s'}           = 'Das Feld %s konnte nicht aktualisiert werden.';
    $Self->{Translation}->{'Need ValidID'}                            = 'Benötige ValidID.';
    $Self->{Translation}->{'Need ID'}                                 = 'Benötige ID.';
    $Self->{Translation}->{'Could not get data for dynamic field %s'} = 'Es konnten keine Daten für das dynamische Feld %s abgerufen werden.';
    $Self->{Translation}->{'Undefined subaction.'}                    = 'Undefinierte Unteraktion.';

    # SysConfig
    $Self->{Translation}->{'Dynamic Fields Freetext List Backend GUI'}          = 'Dynamic-Fields-Oberfläche für Freitextfelder mit Liste';
    $Self->{Translation}->{'Dynamic field backend registration.'}               = 'Backend-Registrierung für dynamische Felder.';
    $Self->{Translation}->{'Frontend module registration for the admin interface.'} =
        'Frontend-Modulregistrierung für das Administrator-Interface.';

    return 1;
}

1;
