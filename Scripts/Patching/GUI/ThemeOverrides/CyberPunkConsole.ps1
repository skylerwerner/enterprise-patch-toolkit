# DOTS formatting comment

<#
    .SYNOPSIS
        WPF GUI launcher for Invoke-Patch.
    .DESCRIPTION
        Provides a graphical front-end for Invoke-Patch with parameter selection,
        live progress tracking, and a color-coded results grid.

        Requires the PowerShell profile to be loaded (Invoke-Patch, Main-Switch,
        and all modules must already be available in the session).

        Use -DryRun to test the GUI with simulated data (no network or profile
        required).

        Written by Skyler Werner
        Date: 2026/04/15
        Version 1.0.0
    .PARAMETER DryRun
        Runs the GUI with simulated mock data instead of calling Invoke-Patch.
        Useful for testing the UI without network access or a loaded profile.
    .EXAMPLE
        .\Invoke-PatchGUI.ps1 -DryRun
#>

param(
    [Switch]$DryRun,
    [ValidateSet('Patch','Version')]
    [string]$Mode = 'Patch'
)


# ============================================================================
#  Assemblies
# ============================================================================

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms


# ============================================================================
#  Shared helpers
# ============================================================================
# Get-MainSwitchNames, Get-MainSwitchListPaths, New-MockPatchResults,
# ConvertTo-DisplayRow, and the preference helpers live in
# Invoke-PatchGUI.Shared.ps1 (one directory up). That keeps this
# override from silently drifting when canonical behavior changes.

. (Join-Path $PSScriptRoot '..\Invoke-PatchGUI.Shared.ps1')


# ============================================================================
#  XAML Window Definition
# ============================================================================

[xml]$xaml = @"
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="[ INVOKE-PATCH // CYBERPUNK CONSOLE ]"
    Width="1050" Height="780"
    MinWidth="900" MinHeight="650"
    WindowStartupLocation="CenterScreen"
    Background="#000000"
    FontFamily="Consolas">

    <Window.Resources>
        <!-- ============================================================ -->
        <!--  Color palette (must be first, other styles reference these) -->
        <!-- ============================================================ -->
        <SolidColorBrush x:Key="Bg"          Color="#000000"/>
        <SolidColorBrush x:Key="Surface"     Color="#080810"/>
        <SolidColorBrush x:Key="Overlay"     Color="#101018"/>
        <SolidColorBrush x:Key="Border"      Color="#00E0FF"/>
        <SolidColorBrush x:Key="Hover"       Color="#001830"/>
        <SolidColorBrush x:Key="Text"        Color="#00E0FF"/>
        <SolidColorBrush x:Key="SubText"     Color="#0088AA"/>
        <SolidColorBrush x:Key="Blue"        Color="#00E0FF"/>
        <SolidColorBrush x:Key="Green"       Color="#00E0FF"/>
        <SolidColorBrush x:Key="Red"         Color="#00A0CC"/>

        <!-- Shared text styles -->
        <Style x:Key="LabelStyle" TargetType="TextBlock">
            <Setter Property="Foreground" Value="{StaticResource Text}"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="VerticalAlignment" Value="Center"/>
            <Setter Property="Margin" Value="0,0,8,0"/>
        </Style>
        <Style x:Key="SectionHeader" TargetType="TextBlock">
            <Setter Property="Foreground" Value="{StaticResource Blue}"/>
            <Setter Property="FontSize" Value="14"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Margin" Value="0,0,0,6"/>
        </Style>

        <!-- ============================================================ -->
        <!--  TextBox ControlTemplate                                     -->
        <!-- ============================================================ -->
        <Style TargetType="TextBox">
            <Setter Property="Foreground"  Value="{StaticResource Text}"/>
            <Setter Property="FontSize"    Value="13"/>
            <Setter Property="CaretBrush"  Value="{StaticResource Text}"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="TextBox">
                        <Border Background="{StaticResource Overlay}"
                                BorderBrush="{StaticResource Border}"
                                BorderThickness="1" CornerRadius="0"
                                Padding="5,3">
                            <ScrollViewer x:Name="PART_ContentHost"
                                          VerticalAlignment="Center"/>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- ============================================================ -->
        <!--  Button ControlTemplate                                      -->
        <!-- ============================================================ -->
        <Style TargetType="Button">
            <Setter Property="Background"  Value="{StaticResource Overlay}"/>
            <Setter Property="Foreground"  Value="{StaticResource Text}"/>
            <Setter Property="BorderBrush" Value="{StaticResource Border}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="FontSize"    Value="13"/>
            <Setter Property="Cursor"      Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="bd"
                                Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="0" Padding="10,4">
                            <ContentPresenter HorizontalAlignment="Center"
                                              VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="bd" Property="Opacity"
                                        Value="0.4"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- ============================================================ -->
        <!--  ComboBox toggle button (the main box + arrow)               -->
        <!-- ============================================================ -->
        <ControlTemplate x:Key="ComboBoxToggle" TargetType="ToggleButton">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition/>
                    <ColumnDefinition Width="28"/>
                </Grid.ColumnDefinitions>
                <Border x:Name="bd" Grid.ColumnSpan="2"
                        Background="{StaticResource Overlay}"
                        BorderBrush="{StaticResource Border}"
                        BorderThickness="1" CornerRadius="0"/>
                <!-- dropdown arrow -->
                <Path Grid.Column="1" HorizontalAlignment="Center"
                      VerticalAlignment="Center"
                      Data="M 0 0 L 5 5 L 10 0 Z"
                      Fill="{StaticResource SubText}"/>
            </Grid>
            <ControlTemplate.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter TargetName="bd" Property="Background"
                            Value="{StaticResource Hover}"/>
                </Trigger>
            </ControlTemplate.Triggers>
        </ControlTemplate>

        <!-- ComboBox editable textbox -->
        <ControlTemplate x:Key="ComboBoxTextBox" TargetType="TextBox">
            <Border x:Name="PART_ContentHost" Focusable="False"
                    Background="Transparent"/>
        </ControlTemplate>

        <!-- ComboBox full style -->
        <Style TargetType="ComboBox">
            <Setter Property="Foreground"    Value="{StaticResource Text}"/>
            <Setter Property="FontSize"      Value="13"/>
            <Setter Property="Height"        Value="28"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ComboBox">
                        <Grid>
                            <ToggleButton x:Name="ToggleButton"
                                Template="{StaticResource ComboBoxToggle}"
                                Focusable="False" ClickMode="Press"
                                IsChecked="{Binding IsDropDownOpen, Mode=TwoWay,
                                    RelativeSource={RelativeSource TemplatedParent}}"/>
                            <ContentPresenter x:Name="ContentSite"
                                IsHitTestVisible="False"
                                Content="{TemplateBinding SelectionBoxItem}"
                                ContentTemplate="{TemplateBinding SelectionBoxItemTemplate}"
                                Margin="8,2,28,2"
                                VerticalAlignment="Center"
                                HorizontalAlignment="Left"/>
                            <TextBox x:Name="PART_EditableTextBox"
                                Style="{x:Null}"
                                Template="{StaticResource ComboBoxTextBox}"
                                IsReadOnly="{TemplateBinding IsReadOnly}"
                                Foreground="{StaticResource Text}"
                                CaretBrush="{StaticResource Text}"
                                Background="Transparent"
                                Margin="6,2,28,2"
                                VerticalAlignment="Center"
                                HorizontalAlignment="Left"
                                Focusable="True"
                                Visibility="Hidden"/>
                            <Popup x:Name="Popup" Placement="Bottom"
                                IsOpen="{TemplateBinding IsDropDownOpen}"
                                AllowsTransparency="True" Focusable="False"
                                PopupAnimation="Slide">
                                <Grid x:Name="DropDown"
                                      MinWidth="{TemplateBinding ActualWidth}"
                                      MaxHeight="{TemplateBinding MaxDropDownHeight}"
                                      SnapsToDevicePixels="True">
                                    <Border x:Name="DropDownBorder"
                                            Background="{StaticResource Overlay}"
                                            BorderBrush="{StaticResource Border}"
                                            BorderThickness="1" CornerRadius="0"
                                            Margin="0,1,0,0"/>
                                    <ScrollViewer Margin="1,2" SnapsToDevicePixels="True">
                                        <StackPanel IsItemsHost="True"
                                            KeyboardNavigation.DirectionalNavigation="Contained"/>
                                    </ScrollViewer>
                                </Grid>
                            </Popup>
                        </Grid>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsEditable" Value="True">
                                <Setter Property="IsTabStop" Value="False"/>
                                <Setter TargetName="PART_EditableTextBox"
                                        Property="Visibility" Value="Visible"/>
                                <Setter TargetName="ContentSite"
                                        Property="Visibility" Value="Hidden"/>
                            </Trigger>
                            <Trigger Property="HasItems" Value="False">
                                <Setter TargetName="DropDownBorder"
                                        Property="MinHeight" Value="60"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- ComboBox dropdown items -->
        <Style TargetType="ComboBoxItem">
            <Setter Property="Foreground" Value="{StaticResource Text}"/>
            <Setter Property="FontSize"   Value="13"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ComboBoxItem">
                        <Border x:Name="bd" Padding="6,4"
                                Background="Transparent">
                            <ContentPresenter/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsHighlighted" Value="True">
                                <Setter TargetName="bd" Property="Background"
                                        Value="{StaticResource Hover}"/>
                            </Trigger>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="bd" Property="Background"
                                        Value="{StaticResource Hover}"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- ============================================================ -->
        <!--  CheckBox ControlTemplate                                    -->
        <!-- ============================================================ -->
        <Style x:Key="CheckBoxStyle" TargetType="CheckBox">
            <Setter Property="Foreground" Value="{StaticResource Text}"/>
            <Setter Property="FontSize"   Value="13"/>
            <Setter Property="Margin"     Value="0,2,16,2"/>
            <Setter Property="Cursor"     Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="CheckBox">
                        <StackPanel Orientation="Horizontal"
                                    VerticalAlignment="Center">
                            <Border x:Name="box" Width="16" Height="16"
                                    Background="{StaticResource Overlay}"
                                    BorderBrush="{StaticResource Border}"
                                    BorderThickness="1" CornerRadius="0"
                                    Margin="0,0,6,0">
                                <Path x:Name="check"
                                      Data="M 2 6 L 6 10 L 12 2"
                                      Stroke="{StaticResource Green}"
                                      StrokeThickness="2"
                                      Visibility="Collapsed"
                                      VerticalAlignment="Center"
                                      HorizontalAlignment="Center"/>
                            </Border>
                            <ContentPresenter VerticalAlignment="Center"/>
                        </StackPanel>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsChecked" Value="True">
                                <Setter TargetName="check" Property="Visibility"
                                        Value="Visible"/>
                                <Setter TargetName="box" Property="BorderBrush"
                                        Value="{StaticResource Green}"/>
                            </Trigger>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="box" Property="Background"
                                        Value="{StaticResource Hover}"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- ============================================================ -->
        <!--  Mode slider toggle - CYBERPUNK CONSOLE (electric cyan)       -->
        <!--  Checked   = Patch mode (knob right, cyan track)              -->
        <!--  Unchecked = Audit mode (knob left, dim track)                -->
        <!-- ============================================================ -->
        <Style x:Key="ModeToggle" TargetType="CheckBox">
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Focusable" Value="False"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="CheckBox">
                        <Border x:Name="track"
                                Width="44" Height="22"
                                CornerRadius="0"
                                Background="#101018"
                                BorderBrush="#005566"
                                BorderThickness="1">
                            <Border x:Name="knob"
                                    Width="16" Height="16"
                                    CornerRadius="0"
                                    Background="#006080"
                                    HorizontalAlignment="Left"
                                    Margin="2,0,0,0"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsChecked" Value="True">
                                <Setter TargetName="track" Property="Background"
                                        Value="#00E0FF"/>
                                <Setter TargetName="track" Property="BorderBrush"
                                        Value="#50F0FF"/>
                                <Setter TargetName="knob" Property="HorizontalAlignment"
                                        Value="Right"/>
                                <Setter TargetName="knob" Property="Margin"
                                        Value="0,0,2,0"/>
                                <Setter TargetName="knob" Property="Background"
                                        Value="#000000"/>
                            </Trigger>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="track" Property="BorderBrush"
                                        Value="#00AAD0"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- ============================================================ -->
        <!--  DataGrid styles                                             -->
        <!-- ============================================================ -->
        <Style TargetType="DataGridColumnHeader">
            <Setter Property="Background"      Value="{StaticResource Overlay}"/>
            <Setter Property="Foreground"       Value="{StaticResource SubText}"/>
            <Setter Property="FontWeight"       Value="SemiBold"/>
            <Setter Property="FontSize"         Value="13"/>
            <Setter Property="Padding"          Value="8,6"/>
            <Setter Property="BorderBrush"      Value="{StaticResource Border}"/>
            <Setter Property="BorderThickness"  Value="0,0,1,1"/>
        </Style>

        <Style TargetType="DataGridCell">
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Padding"         Value="4,2"/>
            <Setter Property="Foreground"      Value="{StaticResource Text}"/>
            <Style.Triggers>
                <Trigger Property="IsSelected" Value="True">
                    <Setter Property="Background" Value="{StaticResource Hover}"/>
                    <Setter Property="Foreground" Value="{StaticResource Text}"/>
                </Trigger>
            </Style.Triggers>
        </Style>

        <Style TargetType="DataGridRow">
            <Style.Triggers>
                <Trigger Property="IsSelected" Value="True">
                    <Setter Property="Background" Value="{StaticResource Hover}"/>
                </Trigger>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="#001830"/>
                </Trigger>
            </Style.Triggers>
        </Style>
        <!-- ============================================================ -->
        <!--  ScrollBar thumb                                             -->
        <!-- ============================================================ -->
        <Style x:Key="ScrollThumb" TargetType="Thumb">
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Thumb">
                        <Border CornerRadius="0" Background="#003040"
                                Margin="1"/>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Vertical ScrollBar -->
        <Style TargetType="ScrollBar">
            <Setter Property="Width" Value="10"/>
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ScrollBar">
                        <Grid>
                            <Track x:Name="PART_Track" IsDirectionReversed="True">
                                <Track.Thumb>
                                    <Thumb Style="{StaticResource ScrollThumb}"/>
                                </Track.Thumb>
                            </Track>
                        </Grid>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
            <Style.Triggers>
                <Trigger Property="Orientation" Value="Horizontal">
                    <Setter Property="Width" Value="Auto"/>
                    <Setter Property="Height" Value="10"/>
                    <Setter Property="Template">
                        <Setter.Value>
                            <ControlTemplate TargetType="ScrollBar">
                                <Grid>
                                    <Track x:Name="PART_Track">
                                        <Track.Thumb>
                                            <Thumb Style="{StaticResource ScrollThumb}"/>
                                        </Track.Thumb>
                                    </Track>
                                </Grid>
                            </ControlTemplate>
                        </Setter.Value>
                    </Setter>
                </Trigger>
            </Style.Triggers>
        </Style>

        <!-- Default ToolTip: cap width and wrap the text so long
             param descriptions don't stretch across the whole screen. -->
        <Style TargetType="ToolTip">
            <Setter Property="MaxWidth" Value="320"/>
            <Setter Property="ContentTemplate">
                <Setter.Value>
                    <DataTemplate>
                        <TextBlock Text="{Binding}" TextWrapping="Wrap"/>
                    </DataTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>

    <Grid Margin="24">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <!-- === HEADER BAR === -->
        <Border Grid.Row="0" Background="#080810" CornerRadius="0"
                BorderBrush="#00E0FF" BorderThickness="2"
                Padding="24,16" Margin="0,0,0,16">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>

                <!-- App title -->
                <StackPanel Grid.Column="0" Orientation="Horizontal"
                            VerticalAlignment="Center">
                    <Border Width="4" Height="32" Background="#00E0FF"
                            CornerRadius="0" Margin="0,0,14,0"/>
                    <StackPanel>
                        <TextBlock Name="lblTitle" Text="INVOKE-PATCH"
                                   FontSize="22" FontWeight="Bold"
                                   Foreground="#00E0FF" FontFamily="Consolas"/>
                        <TextBlock Name="lblSubtitle"
                                   Text="// CYBER REMEDIATION CONSOLE v1.0"
                                   FontSize="10" Foreground="#0088AA"
                                   Margin="0,2,0,0"
                                   FontFamily="Consolas"/>
                    </StackPanel>
                </StackPanel>

                <!-- Mode slider toggle (Consolas labels) -->
                <StackPanel Grid.Column="2" Orientation="Horizontal"
                            VerticalAlignment="Center"
                            Margin="0,0,24,0">
                    <TextBlock Name="lblModeVersion" Text="AUDIT"
                               FontSize="11" FontWeight="Bold"
                               FontFamily="Consolas"
                               Foreground="#0088AA"
                               VerticalAlignment="Center"
                               Margin="0,0,10,0"
                               ToolTip="Audit mode: check installed versions without patching (runs Invoke-Version)."/>
                    <CheckBox Name="tglMode" IsChecked="True"
                              Style="{StaticResource ModeToggle}"
                              VerticalAlignment="Center"
                              ToolTip="Toggle between Patch and Audit modes."/>
                    <TextBlock Name="lblModePatch" Text="PATCH"
                               FontSize="11" FontWeight="Bold"
                               FontFamily="Consolas"
                               Foreground="#00E0FF"
                               VerticalAlignment="Center"
                               Margin="10,0,0,0"
                               ToolTip="Patch mode: run the full remediation (runs Invoke-Patch)."/>
                </StackPanel>

                <!-- Action buttons -->
                <StackPanel Grid.Column="3" Orientation="Horizontal"
                            VerticalAlignment="Center">
                    <Button Name="btnRun" Content="[ EXECUTE ]"
                            Width="130" Height="36" FontSize="14" FontWeight="Bold"
                            Margin="0,0,10,0" Background="#00E0FF" Foreground="#000000"
                            BorderBrush="#00E0FF" BorderThickness="2"/>
                    <Button Name="btnCancel" Content="[ ABORT ]"
                            Width="100" Height="36" FontSize="14" FontWeight="Bold"
                            IsEnabled="False" Background="#000000" Foreground="#FF2020"
                            BorderBrush="#FF2020" BorderThickness="2"/>
                </StackPanel>
            </Grid>
        </Border>

        <!-- === PARAMETERS PANEL === -->
        <Border Grid.Row="1" Background="#080810" CornerRadius="0"
                BorderBrush="#00E0FF" BorderThickness="1"
                Padding="24,20" Margin="0,0,0,14">
            <StackPanel>
                <TextBlock Style="{StaticResource SectionHeader}" Text=">> CONFIGURATION"
                           Margin="0,0,0,14"/>

                <!-- Row 1: Software + Machine -->
                <Grid Margin="0,0,0,14">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="240"/>
                        <ColumnDefinition Width="30"/>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>

                    <TextBlock Grid.Column="0" Style="{StaticResource LabelStyle}"
                               Text="TARGET:"/>
                    <ComboBox Grid.Column="1" Name="cmbSoftware"
                              FontSize="13" IsEditable="True"/>

                    <TextBlock Grid.Column="3" Style="{StaticResource LabelStyle}"
                               Text="HOST:"
                               ToolTip="Single computer name or path to a .txt list file."/>
                    <TextBox Grid.Column="4" Name="txtMachine"
                             FontSize="13" Margin="0,0,10,0"/>
                    <Button Grid.Column="5" Name="btnBrowse" Content="SCAN"
                            Width="80" FontSize="12"/>
                </Grid>

                <!-- Row 2: Options -->
                <Grid>
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>

                    <!-- Switches (collapsed in Audit mode) -->
                    <WrapPanel Name="pnlSwitches" Grid.Column="0" VerticalAlignment="Center">
                        <CheckBox Name="chkForce"       Style="{StaticResource CheckBoxStyle}"
                                  Content="Force"
                                  ToolTip="Run the patch on every targeted machine, including ones already compliant with the target version and ones with no detectable version info (e.g. folder-based installs)."/>
                        <CheckBox Name="chkNoCopy"      Style="{StaticResource CheckBoxStyle}"
                                  Content="NoCopy"
                                  ToolTip="Skip copying installer files to the target machines. Use when the installer is already local."/>
                        <CheckBox Name="chkCollectLogs" Style="{StaticResource CheckBoxStyle}"
                                  Content="CollectLogs"
                                  ToolTip="After patching, pull per-machine install logs back from each remote machine."/>
                    </WrapPanel>

                    <!-- Timeouts (collapsed in Audit mode) -->
                    <StackPanel Name="pnlTimeouts" Grid.Column="1" Orientation="Horizontal">
                        <TextBlock Style="{StaticResource LabelStyle}"
                                   Text="Copy Timeout"
                                   ToolTip="Forced copy timeout in minutes (0-120). Overrides the default dynamic timeout based on file size."/>
                        <TextBox Name="txtCopyTimeout" Width="55"
                                 FontSize="13" Margin="0,0,4,0"/>
                        <TextBlock Style="{StaticResource LabelStyle}"
                                   Text="min" Foreground="#0088AA"
                                   Margin="0,0,20,0"/>
                        <TextBlock Style="{StaticResource LabelStyle}"
                                   Text="Total Timeout"
                                   ToolTip="Forced patching timeout in minutes (0-240). Caps how long each machine's install is allowed to run before it's killed as timed-out."/>
                        <TextBox Name="txtTimeout" Width="55"
                                 FontSize="13" Margin="0,0,4,0"/>
                        <TextBlock Style="{StaticResource LabelStyle}"
                                   Text="min" Foreground="#0088AA"/>
                    </StackPanel>
                </Grid>
            </StackPanel>
        </Border>

        <!-- === PROGRESS PANEL === -->
        <Border Grid.Row="2" Background="#080810" CornerRadius="0"
                BorderBrush="#00E0FF" BorderThickness="1"
                Padding="24,16" Margin="0,0,0,14"
                Name="pnlProgress" Visibility="Collapsed">
            <StackPanel>
                <TextBlock Name="lblStatus" Foreground="#0088AA" FontSize="13"
                           Margin="0,0,0,10"
                           Text="Waiting..."/>
                <ProgressBar Name="prgBar" Height="4" Minimum="0" Maximum="100"
                             Background="#001020" Foreground="#00E0FF"/>
            </StackPanel>
        </Border>

        <!-- === RESULTS PANEL === -->
        <Border Grid.Row="3" Background="#080810" CornerRadius="0"
                BorderBrush="#00E0FF" BorderThickness="1"
                Padding="24,20">
            <Grid>
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                </Grid.RowDefinitions>

                <TextBlock Grid.Row="0" Name="lblResultsHeader"
                           Style="{StaticResource SectionHeader}"
                           Text=">> OUTPUT STREAM" Margin="0,0,0,10"/>

                <DataGrid Grid.Row="1" Name="dgResults"
                          AutoGenerateColumns="False"
                          IsReadOnly="True"
                          CanUserSortColumns="True"
                          CanUserReorderColumns="True"
                          CanUserResizeColumns="True"
                          GridLinesVisibility="None"
                          HeadersVisibility="Column"
                          AlternatingRowBackground="#0A0A14"
                          Background="#080810"
                          RowBackground="#080810"
                          Foreground="#00E0FF"
                          BorderThickness="0"
                          FontSize="13">
                    <DataGrid.Columns>
                        <DataGridTextColumn Header="IP Address"    Binding="{Binding IPAddress}"    Width="110"/>
                        <DataGridTextColumn Header="Computer"      Binding="{Binding ComputerName}" Width="130"/>
                        <DataGridTextColumn Header="Status"        Binding="{Binding Status}"       Width="75"/>
                        <DataGridTextColumn Header="Software"      Binding="{Binding SoftwareName}" Width="120"/>
                        <DataGridTextColumn Header="Version"       Binding="{Binding Version}"      Width="120"/>
                        <DataGridTextColumn Header="Compliant"     Binding="{Binding Compliant}"    Width="80"/>
                        <DataGridTextColumn Header="New Version"   Binding="{Binding NewVersion}"   Width="120"/>
                        <DataGridTextColumn Header="Exit Code"     Binding="{Binding ExitCode}"     Width="75"/>
                        <DataGridTextColumn Header="Comment"       Binding="{Binding Comment}"      Width="*"/>
                    </DataGrid.Columns>
                </DataGrid>

                <!-- Live progress grid: occupies the same slot as dgResults
                     and is swapped in while a run is active.
                     Scrollbar visibility is pinned (Horizontal=Disabled
                     since the State column fills available width, and
                     Vertical=Visible so the auto-show/hide can't fire on
                     every pollTimer tick). Update-ProgressGrid does
                     Items.Clear + re-add each refresh, which triggers
                     a layout pass; with Auto scrollbars the ScrollViewer
                     briefly shows bars mid-layout when the window sits
                     near the content boundary, producing an edge flicker
                     that gets worse on themes with conspicuous scrollbar
                     styling (like the cyberpunk cyan thumb). -->
                <DataGrid Grid.Row="1" Name="dgProgress"
                          Visibility="Collapsed"
                          ScrollViewer.HorizontalScrollBarVisibility="Disabled"
                          ScrollViewer.VerticalScrollBarVisibility="Visible"
                          AutoGenerateColumns="False"
                          IsReadOnly="True"
                          CanUserSortColumns="False"
                          CanUserReorderColumns="False"
                          CanUserResizeColumns="True"
                          GridLinesVisibility="None"
                          HeadersVisibility="Column"
                          AlternatingRowBackground="#0A0A14"
                          Background="#080810"
                          RowBackground="#080810"
                          Foreground="#00E0FF"
                          BorderThickness="0"
                          FontSize="13">
                    <DataGrid.Columns>
                        <DataGridTextColumn Header="Computer" Binding="{Binding Computer}"       Width="160"/>
                        <DataGridTextColumn Header="Elapsed"  Binding="{Binding ElapsedDisplay}" Width="90"/>
                        <DataGridTextColumn Header="Phase"    Binding="{Binding Phase}"          Width="180"/>
                        <DataGridTextColumn Header="State"    Binding="{Binding State}"          Width="*"/>
                    </DataGrid.Columns>
                </DataGrid>
            </Grid>
        </Border>

        <!-- === FOOTER === -->
        <Grid Grid.Row="4" Margin="0,12,0,0">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>

            <TextBlock Grid.Column="0" Name="lblResultCount"
                       Foreground="#0088AA" FontSize="12"
                       VerticalAlignment="Center" Text=""/>
            <StackPanel Grid.Column="2" Orientation="Horizontal">
                <Button Name="btnTheme" Content="[ THEME ]"
                        Width="110" Height="30" FontSize="12"
                        Margin="0,0,14,0"
                        ToolTip="Switch theme. Opens the Gallery."/>
                <Button Name="btnSort" Content="SORT"
                        Width="110" Height="30" FontSize="12"
                        Margin="0,0,8,0" IsEnabled="False"/>
                <Button Name="btnExport" Content="EXFILTRATE"
                        Width="110" Height="30" FontSize="12"
                        IsEnabled="False"/>
            </StackPanel>
        </Grid>
    </Grid>
</Window>
"@


# ============================================================================
#  Build the WPF window
# ============================================================================

$reader = (New-Object System.Xml.XmlNodeReader $xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)

# Map named controls to variables
$controlNames = @(
    'lblTitle', 'lblSubtitle',
    'tglMode', 'lblModePatch', 'lblModeVersion',
    'cmbSoftware', 'txtMachine', 'btnBrowse',
    'pnlSwitches', 'chkForce', 'chkNoCopy', 'chkCollectLogs',
    'pnlTimeouts', 'txtCopyTimeout', 'txtTimeout',
    'btnRun', 'btnCancel',
    'pnlProgress', 'lblStatus', 'prgBar',
    'lblResultsHeader', 'dgResults', 'dgProgress',
    'lblResultCount', 'btnSort', 'btnExport', 'btnTheme'
)
foreach ($name in $controlNames) {
    Set-Variable -Name $name -Value $window.FindName($name)
}


# ============================================================================
#  Populate Software dropdown
# ============================================================================

$softwareNames = @(Get-MainSwitchNames)

# Fallback list for DryRun or when Main-Switch.ps1 is not found
if ($softwareNames.Count -eq 0) {
    $softwareNames = @(
        'Chrome', 'Edge', 'Firefox', 'Reader', 'Java',
        'Teams', 'Zoom', 'VMware', 'Defender', 'Trellix'
    )
}

foreach ($sw in $softwareNames) {
    $cmbSoftware.Items.Add($sw) > $null
}

# Load listPath mapping from Main-Switch so the Machine field can
# auto-populate when the admin picks a software target.
$script:listPathMap = Get-MainSwitchListPaths

# Auto-populate Machine field with the selected software's listPath.
# Admins can still overwrite with a single computer name or a different
# file path; the Run handler routes -TargetList vs -TargetMachine based
# on what's actually in the box.
$cmbSoftware.Add_SelectionChanged({
    $selected = $cmbSoftware.SelectedItem
    if ($selected -and $script:listPathMap.ContainsKey($selected)) {
        $txtMachine.Text = $script:listPathMap[$selected]
    }
})

if ($DryRun) {
    $window.Title = "Invoke-Patch  [DryRun Mode]"
}


# ============================================================================
#  Mode slider (Patch <-> Audit) - CYBERPUNK CONSOLE
# ============================================================================

$script:mode = 'Patch'

function Set-SampleMode {
    param(
        [ValidateSet('Patch','Version')]
        [string]$NewMode
    )

    $script:mode = $NewMode
    $isPatch     = ($NewMode -eq 'Patch')
    $vis         = if ($isPatch) {
        [System.Windows.Visibility]::Visible
    } else {
        [System.Windows.Visibility]::Collapsed
    }

    $pnlSwitches.Visibility = $vis
    $pnlTimeouts.Visibility = $vis

    foreach ($col in $dgResults.Columns) {
        if ($col.Header -in @('New Version','Exit Code','Comment')) {
            $col.Visibility = $vis
        }
    }

    $bright = [Windows.Media.Brush][Windows.Media.BrushConverter]::new().ConvertFrom('#00E0FF')
    $dim    = [Windows.Media.Brush][Windows.Media.BrushConverter]::new().ConvertFrom('#0088AA')
    $lblModePatch.Foreground   = if ($isPatch) { $bright } else { $dim }
    $lblModeVersion.Foreground = if ($isPatch) { $dim }    else { $bright }

    $lblTitle.Text    = "INVOKE-$($NewMode.ToUpper())"
    $lblSubtitle.Text = if ($isPatch) { '// CYBER REMEDIATION CONSOLE v1.0' }
                        else          { '// CYBER AUDIT CONSOLE v1.0' }

    $dryMarker     = if ($DryRun) { '  [DryRun Mode]' } else { '' }
    $window.Title  = "Invoke-$NewMode$dryMarker"
}

$tglMode.Add_Checked({   Set-SampleMode -NewMode 'Patch'   })
$tglMode.Add_Unchecked({ Set-SampleMode -NewMode 'Version' })

Set-SampleMode -NewMode 'Patch'


# ============================================================================
#  Shared state for background work
# ============================================================================

$script:runspace       = $null
$script:psInstance     = $null
$script:asyncHandle    = $null
$script:isRunning      = $false
$script:resultData     = @()


# ============================================================================
#  Browse button
# ============================================================================

$btnBrowse.Add_Click({
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Title  = "Select Machine List"
    $dialog.Filter = "Text files (*.txt)|*.txt|All files (*.*)|*.*"
    $dialog.InitialDirectory = "$env:USERPROFILE\Desktop\Lists"

    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $txtMachine.Text = $dialog.FileName
    }
})


# ============================================================================
#  Progress-view helpers (mirror canonical Invoke-PatchGUI contract)
# ============================================================================

# Sort priority for Update-ProgressGrid. Running first (so in-flight work
# stays at the top), then Completed / Failed / Queued.
$script:progressStateOrder = @{ 'Running' = 1; 'Completed' = 2; 'Failed' = 3; 'Queued' = 4 }

# Within the Running bucket, show further-along phases near the top so
# the admin's eye lands on the machines closest to finishing.
$script:progressPhaseOrder = @{
    'Pinging'       = 1
    'Probing WinRM' = 1
    'DNS Lookup'    = 2
    'Version Check' = 3
    'Copying Files' = 4
    'Patching'      = 5
    'Verifying'     = 6
}

function Format-ElapsedSpan {
    param([TimeSpan]$Span)
    if ($null -eq $Span -or $Span.Ticks -le 0) { return '-' }
    if ($Span.TotalMinutes -ge 1) {
        return "{0}m {1:D2}s" -f [math]::Floor($Span.TotalMinutes), $Span.Seconds
    }
    return "{0}s" -f [math]::Floor($Span.TotalSeconds)
}

function Show-ProgressView {
    $lblResultsHeader.Text = '>> PROGRESS STREAM'
    $dgResults.Visibility  = [System.Windows.Visibility]::Collapsed
    $dgProgress.Visibility = [System.Windows.Visibility]::Visible
    $dgProgress.Items.Clear()
}

function Show-ResultsView {
    $lblResultsHeader.Text = '>> OUTPUT STREAM'
    $dgProgress.Visibility = [System.Windows.Visibility]::Collapsed
    $dgResults.Visibility  = [System.Windows.Visibility]::Visible
    $dgProgress.Items.Clear()
}

function Update-ProgressGrid {
    # Reads the synchronized ProgressSink the background runspace (or
    # the DryRun simulator) writes to and re-renders dgProgress + the
    # status line + determinate progress bar.
    if ($null -eq $script:progressSink) { return }

    $snapshot = @()
    $sync = $script:progressSink
    [System.Threading.Monitor]::Enter($sync.SyncRoot)
    try {
        foreach ($v in $sync.Values) { $snapshot += ,$v }
    }
    finally {
        [System.Threading.Monitor]::Exit($sync.SyncRoot)
    }

    if ($snapshot.Count -eq 0) { return }

    $total     = $snapshot.Count
    $completed = @($snapshot | Where-Object { $_.State -eq 'Completed' }).Count
    $failed    = @($snapshot | Where-Object { $_.State -eq 'Failed' }).Count
    $running   = @($snapshot | Where-Object { $_.State -eq 'Running' }).Count
    $queued    = @($snapshot | Where-Object { $_.State -eq 'Queued' }).Count
    $done      = $completed + $failed

    $sorted = $snapshot | Sort-Object @(
        @{ Expression = {
            $s = $_.State
            if ($script:progressStateOrder.ContainsKey($s)) { $script:progressStateOrder[$s] }
            else { 99 }
        }; Ascending = $true }
        @{ Expression = {
            if ($_.State -eq 'Running' -and $_.Phase -and $script:progressPhaseOrder.ContainsKey($_.Phase)) {
                $script:progressPhaseOrder[$_.Phase]
            } else { 0 }
        }; Descending = $true }
        @{ Expression = {
            if ($_.State -eq 'Running' -and $_.StartTime) { $_.StartTime } else { [DateTime]::MaxValue }
        }; Ascending = $true }
        @{ Expression = { $_.Computer }; Ascending = $true }
    )

    $rows = foreach ($entry in $sorted) {
        $phaseDisplay = if ($entry.Phase) { [string]$entry.Phase } else { '-' }
        # Elapsed only matters while Running -- stop ticking once the
        # row lands in Completed/Failed/Queued.
        $elapsedDisplay = if ($entry.State -eq 'Running') {
            Format-ElapsedSpan $entry.Elapsed
        } else { '-' }
        [PSCustomObject]@{
            Computer       = [string]$entry.Computer
            ElapsedDisplay = $elapsedDisplay
            Phase          = $phaseDisplay
            State          = [string]$entry.State
        }
    }

    $dgProgress.Items.Clear()
    foreach ($row in $rows) {
        $dgProgress.Items.Add($row) > $null
    }

    $pct = if ($total -gt 0) { [int](($done / $total) * 100) } else { 0 }
    $prgBar.IsIndeterminate = $false
    $prgBar.Value = $pct

    $runLabel = if ($script:mode -eq 'Version') { 'version check' } else { 'patching' }
    $sw = if ($script:selectedSoftware) { $script:selectedSoftware } else { $cmbSoftware.Text }
    $lblStatus.Text = "Running $sw $runLabel... $done / $total complete (Running: $running  Queued: $queued  Failed: $failed)"
}


# ============================================================================
#  Helper: Populate results grid and update footer/progress
# ============================================================================

function Complete-RunWithResults {
    param([array]$Results)

    # Flip back to the static results grid before repopulating it.
    # No-op on DryRun paths that never called Show-ProgressView.
    Show-ResultsView

    # Flatten array-valued display properties so the WPF grid doesn't
    # render them as "System.Object[]".
    $displayRows = @($Results | ConvertTo-DisplayRow)

    $dgResults.Items.Clear()
    foreach ($row in $displayRows) {
        $dgResults.Items.Add($row) > $null
    }

    # Surface the actual error if the runspace produced an ERROR/Failed row.
    # The Comment carries the exception message from Invoke-Patch/Version;
    # pop it in a MessageBox so the admin can tell what broke instead of
    # staring at a single "ERROR | Failed" row.
    $errorRow = $displayRows | Where-Object {
        $_.ComputerName -eq 'ERROR' -and $_.Status -eq 'Failed'
    } | Select-Object -First 1
    if ($errorRow) {
        $msg = if ($errorRow.Comment) { [string]$errorRow.Comment } else { '(no details)' }
        [System.Windows.MessageBox]::Show(
            "The background cmdlet threw an exception:`n`n$msg",
            "Invoke-$($script:mode) Error", "OK", "Error") > $null
    }

    $total   = $displayRows.Count
    $online  = @($displayRows | Where-Object { $_.Status -eq 'Online' }).Count
    $offline = @($displayRows | Where-Object { $_.Status -eq 'Offline' }).Count
    $lblResultCount.Text = "$total machines  |  $online online  |  $offline offline"

    $prgBar.IsIndeterminate = $false
    $prgBar.Value = 100
    $lblStatus.Text = "Complete - $total results"

    $btnRun.IsEnabled    = $true
    $btnCancel.IsEnabled = $false
    $btnSort.IsEnabled   = ($total -gt 0)
    $btnExport.IsEnabled = ($total -gt 0)
    $btnTheme.IsEnabled  = $true
}


# ============================================================================
#  Run button - launch Invoke-Patch in a background runspace
# ============================================================================

$btnRun.Add_Click({

    # --- Validate software selection ---
    $script:selectedSoftware = $cmbSoftware.Text.Trim()
    $selectedSoftware = $script:selectedSoftware
    if ([string]::IsNullOrWhiteSpace($selectedSoftware)) {
        [System.Windows.MessageBox]::Show(
            "Please select a software target.",
            "Validation", "OK", "Warning")
        return
    }

    # --- UI state: running ---
    $btnRun.IsEnabled    = $false
    $btnCancel.IsEnabled = $true
    $btnSort.IsEnabled   = $false
    $btnExport.IsEnabled = $false
    $btnTheme.IsEnabled  = $false
    $pnlProgress.Visibility = [System.Windows.Visibility]::Visible
    $dgResults.Items.Clear()
    $lblResultCount.Text = ""


    # ----------------------------------------------------------------
    #  DryRun mode: simulate with mock data after a short delay
    # ----------------------------------------------------------------
    if ($DryRun) {

        # Resolve the Machine field into an explicit hostname list so
        # the mock generator renders the user's targets verbatim.
        # Mirrors the live-mode path / single-machine handling below.
        $script:dryRunNames = @()
        $dryText = $txtMachine.Text.Trim()
        if ($dryText) {
            $isPath = ($dryText -match '[\\/]') -or ($dryText -match '\.[a-zA-Z]+$')
            if ($isPath -and (Test-Path $dryText)) {
                $script:dryRunNames = @(
                    Get-Content -Path $dryText -ErrorAction SilentlyContinue |
                        Where-Object { $_ -and $_ -notmatch '^\s*#' } |
                        ForEach-Object { $_.Trim() } |
                        Where-Object { $_ }
                )
            }
            elseif (-not $isPath) {
                $script:dryRunNames = @($dryText)
            }
        }

        $dryLabel = if ($script:mode -eq 'Version') { 'version check' }
                    else                            { 'patching' }

        # Pre-roll mock results so each simulated machine has a known
        # final status. The phase plan below keys off that status so
        # what the user watches in the progress grid matches what lands
        # in the results grid.
        $mockParams = @{
            SoftwareName = $selectedSoftware
            Count        = 15
            Mode         = $script:mode
        }
        if ($script:dryRunNames -and $script:dryRunNames.Count -gt 0) {
            $mockParams.ComputerName = $script:dryRunNames
        }
        $script:dryRunMocks = @(New-MockPatchResults @mockParams)
        $dryCount = $script:dryRunMocks.Count

        $lblStatus.Text         = "[DryRun] Simulating $selectedSoftware $dryLabel on $dryCount machines..."
        $prgBar.IsIndeterminate = $false
        $prgBar.Value           = 0

        # Build per-machine phase plans. Durations mirror the real-run
        # shape compressed so a dry run finishes in well under a minute
        # while staying proportional: Copy/Patch dominate, probes and
        # verification are quick. Random ranges give the grid visible
        # jitter instead of lockstep progression.
        $isVersionModeDry = ($script:mode -eq 'Version')
        $rngDry           = New-Object System.Random
        $plans            = @{}

        foreach ($mock in $script:dryRunMocks) {
            $phases = New-Object System.Collections.Generic.List[object]
            $phases.Add(@{ Name='Pinging'; Seconds=$rngDry.Next(1, 4) }) > $null

            switch ($mock.Status) {
                'Offline' {
                    # Ping failed, WinRM probe failed -> stop here.
                    $phases.Add(@{ Name='Probing WinRM'; Seconds=$rngDry.Next(2, 6) }) > $null
                }
                'Isolated' {
                    # Ping failed but WinRM probe succeeded, run continues.
                    $phases.Add(@{ Name='Probing WinRM'; Seconds=$rngDry.Next(2, 6) }) > $null
                    $phases.Add(@{ Name='Version Check'; Seconds=$rngDry.Next(2, 6) }) > $null
                    if (-not $isVersionModeDry) {
                        $phases.Add(@{ Name='Copying Files'; Seconds=$rngDry.Next(10, 16) }) > $null
                        $phases.Add(@{ Name='Patching';      Seconds=$rngDry.Next(10, 16) }) > $null
                        $phases.Add(@{ Name='Verifying';     Seconds=$rngDry.Next(1, 4)  }) > $null
                    }
                }
                default {
                    # Online: straight to version check and (if patching) the install.
                    $phases.Add(@{ Name='Version Check'; Seconds=$rngDry.Next(2, 6) }) > $null
                    if (-not $isVersionModeDry) {
                        $phases.Add(@{ Name='Copying Files'; Seconds=$rngDry.Next(10, 16) }) > $null
                        $phases.Add(@{ Name='Patching';      Seconds=$rngDry.Next(10, 16) }) > $null
                        $phases.Add(@{ Name='Verifying';     Seconds=$rngDry.Next(1, 4)  }) > $null
                    }
                }
            }

            $plans[$mock.ComputerName] = [PSCustomObject]@{
                Computer    = $mock.ComputerName
                Phases      = $phases
                PhaseIndex  = -1
                StartTime   = $null
                PhaseEndsAt = $null
                State       = 'Queued'
                Phase       = $null
            }
        }
        $script:dryRunPlans = $plans

        # Hardcoded concurrent cap so the Queued bucket is visible on
        # larger target lists.
        $script:dryRunThrottle = 8

        # Seed the progress sink so Update-ProgressGrid has rows on tick 1.
        $script:progressSink = [Hashtable]::Synchronized(@{})
        foreach ($plan in $plans.Values) {
            $script:progressSink[$plan.Computer] = @{
                Computer  = $plan.Computer
                StartTime = $null
                Elapsed   = [TimeSpan]::Zero
                Phase     = $null
                State     = 'Queued'
            }
        }
        Show-ProgressView
        Update-ProgressGrid

        $script:dryRunTimer = New-Object System.Windows.Threading.DispatcherTimer
        $script:dryRunTimer.Interval = [TimeSpan]::FromMilliseconds(250)

        $script:dryRunTimer.Add_Tick({
            $now   = [DateTime]::Now
            $plans = $script:dryRunPlans

            # Advance any Running machine past a phase whose clock expired.
            foreach ($plan in $plans.Values) {
                if ($plan.State -ne 'Running') { continue }
                if ($now -lt $plan.PhaseEndsAt) { continue }

                $plan.PhaseIndex++
                if ($plan.PhaseIndex -ge $plan.Phases.Count) {
                    $plan.State       = 'Completed'
                    $plan.Phase       = $null
                    $plan.PhaseEndsAt = $null
                }
                else {
                    $next             = $plan.Phases[$plan.PhaseIndex]
                    $plan.Phase       = $next.Name
                    $plan.PhaseEndsAt = $now.AddSeconds($next.Seconds)
                }
            }

            # Promote Queued machines up to the throttle cap.
            $runningCount = @($plans.Values | Where-Object { $_.State -eq 'Running' }).Count
            foreach ($plan in $plans.Values) {
                if ($runningCount -ge $script:dryRunThrottle) { break }
                if ($plan.State -ne 'Queued') { continue }

                $plan.State       = 'Running'
                $plan.PhaseIndex  = 0
                $plan.StartTime   = $now
                $first            = $plan.Phases[0]
                $plan.Phase       = $first.Name
                $plan.PhaseEndsAt = $now.AddSeconds($first.Seconds)
                $runningCount++
            }

            # Mirror plan state into the sink so Update-ProgressGrid
            # consumes the same contract the live path writes.
            foreach ($plan in $plans.Values) {
                $elapsed = if ($plan.StartTime) { $now - $plan.StartTime } else { [TimeSpan]::Zero }
                $script:progressSink[$plan.Computer] = @{
                    Computer  = $plan.Computer
                    StartTime = $plan.StartTime
                    Elapsed   = $elapsed
                    Phase     = $plan.Phase
                    State     = $plan.State
                }
            }

            Update-ProgressGrid

            $stillWorking = @($plans.Values | Where-Object {
                $_.State -eq 'Queued' -or $_.State -eq 'Running'
            }).Count
            if ($stillWorking -eq 0) {
                $script:dryRunTimer.Stop()
                $script:resultData = $script:dryRunMocks
                Complete-RunWithResults -Results $script:resultData
                $lblStatus.Text = "[DryRun] Complete - $($script:resultData.Count) simulated results"
            }
        })

        $script:dryRunTimer.Start()
        return
    }


    # ----------------------------------------------------------------
    #  Live mode: run Invoke-Patch or Invoke-Version in a background runspace
    # ----------------------------------------------------------------

    $isVersionMode = ($script:mode -eq 'Version')
    $cmdName       = if ($isVersionMode) { 'Invoke-Version' } else { 'Invoke-Patch' }
    $modeLabel     = if ($isVersionMode) { 'version check' } else { 'patching' }

    $lblStatus.Text         = "Starting $selectedSoftware $modeLabel..."
    $prgBar.IsIndeterminate = $true
    $prgBar.Value           = 0

    # --- Live progress sink shared with the background runspace ---
    # Reset per run so a previous run's machines don't linger. Swap the
    # grid slot to show Progress immediately; rows arrive on the first
    # pollTimer tick once Invoke-RunspacePool has seeded the sink.
    $script:progressSink = [Hashtable]::Synchronized(@{})
    Show-ProgressView

    # --- Build parameter splat as a string ---
    # -PassThru makes the cmdlet emit its results array on the pipeline
    # so the background runspace can capture and display them in the grid.
    # -ProgressSink references a variable injected into the background
    # runspace below -- the backtick keeps it literal through here-string
    # interpolation so it resolves at scriptblock-execution time, not now.
    $paramParts = @()
    $paramParts += "-TargetSoftware '$selectedSoftware'"
    $paramParts += "-PassThru"
    $paramParts += "-ProgressSink `$guiProgressSink"

    $machineText = $txtMachine.Text.Trim()
    if ($machineText) {
        # Detect if the value is a file path (contains a path separator or
        # file extension). If so, use -TargetList so the cmdlet reads it as
        # a list file instead of treating the path as a single computer.
        # If the value matches the auto-populated default, omit the param
        # entirely so Main-Switch resolves the listPath naturally.
        $defaultListPath = if ($script:listPathMap.ContainsKey($selectedSoftware)) {
            $script:listPathMap[$selectedSoftware]
        } else { $null }

        $isPath    = ($machineText -match '[\\/]') -or ($machineText -match '\.[a-zA-Z]+$')
        $isDefault = $defaultListPath -and ($machineText -eq $defaultListPath)

        if ($isDefault) {
            # User left the auto-populated default: let the cmdlet use its
            # Main-Switch listPath naturally (no param needed)
        }
        elseif ($isPath) {
            $paramParts += "-TargetList '$machineText'"
        }
        else {
            $paramParts += "-TargetMachine '$machineText'"
        }
    }

    # Patch-only parameters (skipped in Version mode since Invoke-Version
    # does not accept any of them).
    if (-not $isVersionMode) {
        if ($chkForce.IsChecked)       { $paramParts += "-Force" }
        if ($chkNoCopy.IsChecked)      { $paramParts += "-NoCopy" }
        if ($chkCollectLogs.IsChecked) { $paramParts += "-CollectLogs" }

        $copyTimeoutVal = $txtCopyTimeout.Text.Trim()
        if ($copyTimeoutVal -match '^\d+$') {
            $paramParts += "-CopyTimeout $copyTimeoutVal"
        }

        $timeoutVal = $txtTimeout.Text.Trim()
        if ($timeoutVal -match '^\d+$') {
            $paramParts += "-Timeout $timeoutVal"
        }
    }

    $invokeCmd = "$cmdName " + ($paramParts -join ' ')


    # --- Create background runspace ---
    $script:runspace = [RunspaceFactory]::CreateRunspace()
    $script:runspace.ApartmentState = [System.Threading.ApartmentState]::STA
    $script:runspace.Open()

    # Publish the synchronized sink into the background runspace under the
    # name the generated invokeCmd expects (-ProgressSink $guiProgressSink).
    # Both runspaces hold the same Hashtable reference, so writes from the
    # Invoke-RunspacePool monitor loop are visible to the GUI immediately.
    $script:runspace.SessionStateProxy.SetVariable('guiProgressSink', $script:progressSink)

    $script:psInstance = [PowerShell]::Create()
    $script:psInstance.Runspace = $script:runspace

    # The background runspace needs the same environment as the current session.
    # We dot-source the profile and then call Invoke-Patch, capturing output.
    $profilePath = $PROFILE.CurrentUserCurrentHost
    $scriptBlock = [ScriptBlock]::Create(@"
        try {
            # Load the same profile so all modules and functions are available
            if (Test-Path '$($profilePath -replace "'","''")') {
                . '$($profilePath -replace "'","''")'
            }

            # Run the patch command and capture results
            `$results = @($invokeCmd)

            # Return structured results
            `$results | Where-Object {
                `$_ -is [PSCustomObject] -and
                `$null -ne `$_.PSObject.Properties['ComputerName']
            }
        }
        catch {
            [PSCustomObject]@{
                ComputerName = 'ERROR'
                Status       = 'Failed'
                Comment      = `$_.Exception.Message
                IPAddress    = `$null
                SoftwareName = '$($selectedSoftware -replace "'","''")'
                Version      = `$null
                Compliant    = `$null
                NewVersion   = `$null
                ExitCode     = `$null
            }
        }
"@)

    $script:psInstance.AddScript($scriptBlock)
    $script:asyncHandle = $script:psInstance.BeginInvoke()
    $script:isRunning = $true


    # --- Start polling timer ---
    # 1s matches Invoke-RunspacePool's internal sink refresh rate, so each
    # tick renders fresh phase/elapsed data without lag.
    $script:pollTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:pollTimer.Interval = [TimeSpan]::FromSeconds(1)

    $script:pollTimer.Add_Tick({

        if ($null -eq $script:asyncHandle) { return }

        # Check if the background work is done
        if ($script:asyncHandle.IsCompleted) {

            $script:pollTimer.Stop()
            $script:isRunning = $false

            try {
                $output = @($script:psInstance.EndInvoke($script:asyncHandle))

                $script:resultData = @($output | Where-Object {
                    $_ -is [PSCustomObject] -and
                    $null -ne $_.PSObject.Properties['ComputerName']
                })
            }
            catch {
                $script:resultData = @([PSCustomObject]@{
                    ComputerName = 'ERROR'
                    Status       = 'Failed'
                    Comment      = $_.Exception.Message
                    IPAddress    = $null
                    SoftwareName = $null
                    Version      = $null
                    Compliant    = $null
                    NewVersion   = $null
                    ExitCode     = $null
                })
            }
            finally {
                if ($script:psInstance) {
                    $script:psInstance.Dispose()
                    $script:psInstance = $null
                }
                if ($script:runspace) {
                    $script:runspace.Close()
                    $script:runspace.Dispose()
                    $script:runspace = $null
                }
                $script:asyncHandle = $null
            }

            Complete-RunWithResults -Results $script:resultData
        }
        else {
            # Live progress view: re-render the per-machine table and
            # update the status line + determinate progress bar from
            # the synchronized sink the background runspace writes.
            Update-ProgressGrid
        }
    })

    $script:pollTimer.Start()
})


# ============================================================================
#  Cancel button
# ============================================================================

$btnCancel.Add_Click({
    $lblStatus.Text = "Cancelling..."

    # Stop DryRun timer if active
    if ($script:dryRunTimer) {
        $script:dryRunTimer.Stop()
        $script:dryRunTimer = $null
    }

    # Stop live runspace if active
    if ($script:psInstance) {
        try { $script:psInstance.Stop() } catch { }
    }

    # Flip the grid back to the (empty) Results view so a cancelled
    # run doesn't leave the progress table stuck onscreen.
    Show-ResultsView

    $prgBar.IsIndeterminate = $false
    $prgBar.Value = 0
    $lblStatus.Text = "Cancelled"
    $btnRun.IsEnabled    = $true
    $btnCancel.IsEnabled = $false
    $btnTheme.IsEnabled  = $true
})


# ============================================================================
#  Theme button - open the Gallery as a theme picker
# ============================================================================

$btnTheme.Add_Click({
    if ($script:isRunning) { return }

    $galleryPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'Invoke-PatchGUI-Gallery.ps1'
    if (-not (Test-Path $galleryPath)) {
        [System.Windows.MessageBox]::Show(
            "Gallery not found at:`n$galleryPath",
            "Theme picker",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Warning
        ) | Out-Null
        return
    }

    # Forward session switches so they survive the Gallery -> main-GUI
    # relaunch cycle. -DryRun must not silently drop when the user picks
    # a new theme mid-session; -Mode reads the live toggle state so if
    # the user flipped to Version before opening the Gallery, they come
    # back in Version.
    $argList = @('-NoProfile', '-File', $galleryPath)
    if ($DryRun)        { $argList += '-DryRun' }
    if ($script:mode)   { $argList += @('-Mode', $script:mode) }
    Start-Process -FilePath 'powershell.exe' -ArgumentList $argList
    $window.Close()
})


# ============================================================================
#  Default Sort button (matches Invoke-Patch CLI output order)
# ============================================================================

$btnSort.Add_Click({
    if ($script:resultData.Count -eq 0) { return }

    # Mirrors Invoke-Patch's Format-Table cascade so the GUI button
    # output matches a fresh CLI run. Version-mode results flow
    # through the same cascade cleanly: NewVersion / ExitCode /
    # Comment are null in Version mode and Sort-Object falls
    # straight through to Version + ComputerName.
    $sorted = @($script:resultData | Sort-Object -Property (
        @{ Expression = {
            switch ($_.Status) {
                'Isolated' { 1 }
                'Online'   { 2 }
                'Offline'  { 3 }
                default    { 99 }
            }
        }; Descending = $false },
        @{ Expression = "NewVersion";   Descending = $true  },
        @{ Expression = "ExitCode";     Descending = $true  },
        @{ Expression = "Version";      Descending = $false },
        @{ Expression = "Comment";      Descending = $false },
        @{ Expression = "ComputerName"; Descending = $false }
    ))

    $dgResults.Items.Clear()
    foreach ($row in $sorted) {
        $dgResults.Items.Add($row) > $null
    }
})


# ============================================================================
#  Export CSV button
# ============================================================================

$btnExport.Add_Click({
    if ($script:resultData.Count -eq 0) { return }

    $dialog = New-Object System.Windows.Forms.SaveFileDialog
    $dialog.Title  = "Export Results"
    $dialog.Filter = "CSV files (*.csv)|*.csv"
    $dialog.InitialDirectory = "$env:USERPROFILE\Desktop\Patch-Results"
    $dialog.FileName = "PatchResults_$(Get-Date -Format 'yyyy-MM-dd_HHmm').csv"

    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $exportProps = @(
            "IPAddress", "ComputerName", "Status", "SoftwareName",
            "Version", "Compliant", "NewVersion", "ExitCode", "Comment"
        )

        $script:resultData |
            Select-Object $exportProps |
            Export-Csv -Path $dialog.FileName -NoTypeInformation -Force

        $lblStatus.Text = "Exported to: $($dialog.FileName)"
    }
})


# ============================================================================
#  Cleanup on window close
# ============================================================================

$window.Add_Closing({
    if ($script:pollTimer) {
        $script:pollTimer.Stop()
    }
    if ($script:psInstance) {
        try { $script:psInstance.Stop() } catch { }
        try { $script:psInstance.Dispose() } catch { }
    }
    if ($script:runspace) {
        try { $script:runspace.Close() } catch { }
        try { $script:runspace.Dispose() } catch { }
    }
})


# ============================================================================
#  Show the window
# ============================================================================

$window.ShowDialog() > $null
