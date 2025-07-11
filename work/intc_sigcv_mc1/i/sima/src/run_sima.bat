@echo off
@rem ##############################################################################
@rem #  COPYRIGHT (C) VITESCO TECHNOLOGIES 2021 - ALL RIGHTS RESERVED
@rem #
@rem #  Confidential
@rem #
@rem # The reproduction, transmission or use of this document or its contents is not permitted without express written authority.
@rem #  Offenders will be liable for damages. All rights, including rights created by patent grant or registration of a utility 
@rem #  model or design, are reserved.
@rem #
@rem #---------------------------------------------------------------------------
@rem #   Purpose:   Commandline interface for SiMa GUI
@rem #   Project:   SiMa
@rem #---------------------------------------------------------------------------
@rem #   Filename:  $Workfile:   run_sima.bat  $
@rem #   Revision:  $Revision: 1.1 $
@rem ##############################################################################

@rem +--------------------------------------------------------------------------+
@rem | Set SIMA_SUPPRESS_MESSAGE to True if debug message not to be printed     |
@rem +--------------------------------------------------------------------------+

@set SIMA_SUPPRESS_MESSAGE=

@rem ##############################################################################
@rem | SiMa version that should be used for project                               |
@rem ##############################################################################
    @set PROJECT_SIMA_VERSION=6.2.0


@rem ##############################################################################
@rem | This is path project configuration                                         |
@rem | Always maintain path relative to batch file                                |
@rem | It is optional to change this path                                         |
@rem ##############################################################################
    @set PROJECT_FILE=config.xml


@rem ##############################################################################
@rem | This is path for Antifoni.exe                                              |
@rem | Due to change in path of antifoni this option needs to be given.           |
@rem | Set it to global path                                                      |
@rem ##############################################################################
    @set SIMA_ANTIFONI_EXE=\\vt1.vitesco.com\SMT\did02064\Service\Apps\Antifoni\Antifoni.exe
    
@rem ##############################################################################
@rem | This is path for UCIX.exe, Set it to your local path                       |
@rem | Set UCIX parameters to export Limas spec contents into xml file            |
@rem | EXPORT_PATH Path to create xml file, by default it creates in sima workspace|
@rem ##############################################################################
    @set SIMA_UCIX_EXE=C:\LegacyApp\AutomotiveDataDictionary\UCIX.exe
    @set SIMA_UCIX_PARAMS=/nobar /mode:EXPORT /env:PROD ${CONTAINER_ID} ${EXPORT_PATH}


@rem ##############################################################################
@rem +----------------------------------------------------------------------------+
@rem |            DO NOT CHANGE ANYTHING BELOW                                    |
@rem +----------------------------------------------------------------------------+
@rem ##############################################################################
    @cd %~dp0

@rem +--------------------------------------------------------------------------+
@rem | check OS version and set copy options depends on that                    |
@rem +--------------------------------------------------------------------------+
    @set TOOL_DRIVE=N:\SiMa
    @set LOCAL_DRIVE=C:\Win16App\SiMa
    @set COPY_TOOL=xcopy
    @set COPY_TOOL_FILES=*.*
    @set COPY_TOOL_PARAMS=/E /Q /Y
    @set BATCH_PATH=%cd%
    @call :check_os
    
    @if %OPERATING_SYSTEM%=="Windows7+" (
        @call :init_copytool_settings
    )  
    
    @if not exist %LOCAL_DRIVE%\%PROJECT_SIMA_VERSION%\ (
        @goto :tool_notfound
    )
    
    @if not exist %TOOL_DRIVE%\%PROJECT_SIMA_VERSION%\ (
        @goto :warn_call_tool
    )

@rem +--------------------------------------------------------------------------+
@rem | Get checksum file from Tool and local drive and verify it.               |
@rem +--------------------------------------------------------------------------+
    @set checksum_file=%TOOL_DRIVE%\%PROJECT_SIMA_VERSION%\Tool_cks.txt
    @call :GET_CHECKSUM
    @set tooldrive_checksum=%result%
    
    @set result=
    @set checksum_file=%LOCAL_DRIVE%\%PROJECT_SIMA_VERSION%\Tool_cks.txt
    @call :GET_CHECKSUM
    @set local_checksum=%result%
    
    
    @call :echo_debug ""
    @call :echo_debug "verifying the checksum ..."
    @call :echo_debug ""
    
    @if not "%local_checksum%" == "%tooldrive_checksum%" (
        @goto :update_tool
    )
    @goto :no_copy

@rem +--------------------------------------------------------------------------+
@rem | Tool not available in local drive copy from tool drive                   |
@rem +--------------------------------------------------------------------------+
:tool_notfound 
	@call :echo_debug "Tool not present in local drive!" 
	@call :echo_debug "Copying from %TOOL_DRIVE%\%PROJECT_SIMA_VERSION%\ ..."
	@goto :copy_tool

:update_tool
	@call :echo_debug "Invalid checksum. Copying files from %TOOL_DRIVE%\%PROJECT_SIMA_VERSION%\ %LOCAL_DRIVE%\%PROJECT_SIMA_VERSION%\ to ..."

:copy_tool
	@if not exist %TOOL_DRIVE%\%PROJECT_SIMA_VERSION%\ (
	   @goto :show_error
	)
	@%COPY_TOOL% %TOOL_DRIVE%\%PROJECT_SIMA_VERSION%\%COPY_TOOL_FILES% %LOCAL_DRIVE%\%PROJECT_SIMA_VERSION%\ %COPY_TOOL_PARAMS%
	@goto :call_tool

:no_copy
	@call :echo_debug "Local drive is upto date, local SiMa will be used."
	@goto :call_tool

:warn_call_tool
	@call :echo_debug "Unable to verify validity of local sima version with tool drive."
	@call :echo_debug "local version will be used."
	@call :echo_debug ""

@rem +--------------------------------------------------------------------------+
@rem | call project version SiMa application                                    |
@rem +--------------------------------------------------------------------------+
:call_tool
	@set SIMA_CMD=%LOCAL_DRIVE%\%PROJECT_SIMA_VERSION%\cmd
	@set SIMA_CMD=%SIMA_CMD:\=\\%
	@set SIMA_CMD=%SIMA_CMD: =\ %
	@if not "%PROJECT_FILE%"=="" (
	   @call :SET_CONFIG
	)
	@set ANTIFONI=%SIMA_ANTIFONI_EXE:\=\\%
	@set ANTIFONI=%ANTIFONI: =\ %

	@call :echo_debug "Calling SiMa ..."
	@start " " "%LOCAL_DRIVE%\%PROJECT_SIMA_VERSION%\sima.exe" 
	@goto :eof

:SET_CONFIG
	@set conf_file=%BATCH_PATH%\%PROJECT_FILE%
	@goto :eof

:GET_CHECKSUM
	@for /F "tokens=1 delims=" %%A in ('findstr /R /C:"^CKS = .*$" %checksum_file%') do (
	   @set result=%%A
	)
	@goto :eof

:show_error
	@call :echo_debug "Project SiMa version not avaibale." 
	@call :echo_debug "Check availability of %TOOL_DRIVE%"
	@goto :eof
@rem +------------------------------------------------------------------+
@rem | Check which os batch file is running.                            |
@rem +------------------------------------------------------------------+        
:check_os
    @ver | findstr "XP" > nul
    @if %ERRORLEVEL% == 0 (
        @set OPERATING_SYSTEM="WindowsXP"
    ) else (
        @set OPERATING_SYSTEM="Windows7+"
    )
    @goto :eof
    
@rem +------------------------------------------------------------------+
@rem | Set Windows 7 and above OS paramteres for copy                   |
@rem +------------------------------------------------------------------+       
:init_copytool_settings
	@set LOCAL_DRIVE=C:\LegacyApp\SiMa
	@if "%TOOLS_DRV%"=="" (
	   @set TOOLS_DRV=A:
	)
	@set TOOL_DRIVE=%TOOLS_DRV%\SiMa
	@set COPY_TOOL=robocopy
	@set COPY_TOOL_FILES=
	@set COPY_TOOL_PARAMS=/mir /r:0 /w:0 /NS /np /NC /NJH /NJS /NFL /NDL
	@goto :eof


@rem +------------------------------------------------------------------+
@rem | Print message only if debug is non-empty                         |
@rem +------------------------------------------------------------------+		
:echo_debug
	@setlocal
	@echo on
	@set msg=%~1
	@if "%SIMA_SUPPRESS_MESSAGE%"==""	(
		@if NOT "%msg%"=="" (
            @echo:%msg%
		) else (
            @echo:
		)
	)
	@echo off
	@endlocal
