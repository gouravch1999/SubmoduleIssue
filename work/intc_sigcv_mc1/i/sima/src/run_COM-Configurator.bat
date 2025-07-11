@echo off

REM ##############################################################################
REM #   COPYRIGHT (C) Continental Automotive GmbH 2015
REM #
REM #   ALL RIGHTS RESERVED.
REM #
REM #   The reproduction, transmission or use of this document or its
REM #   contents is not permitted without express written authority.
REM #   Offenders will be liable for damages. All rights, including rights
REM #   created by patent grant or registration of a utility model or design,
REM #   are reserved.
REM #---------------------------------------------------------------------------
REM #   Purpose:   Commandline interface for COM-Configurator 
REM #
REM #   Project:   SiMa
REM #---------------------------------------------------------------------------
REM #   Filename:  $Workfile:   run_COM-Configurator.bat  $
REM #   Revision:  $Revision: 1.1 $
REM #   Author:    $Author: Zhang Yi (uiv00534) (uiv00534) $
REM #   Date:      $Date: 2024/09/03 03:20:57CEST $
REM #
REM ##############################################################################


set CURDRV=%~d0
set CURDIR=%~p0
%CURDRV%
cd %CURDIR%\COM-Configurator
Perl COM-Configurator.pl
cd %CURDIR%

@goto exit
:exit