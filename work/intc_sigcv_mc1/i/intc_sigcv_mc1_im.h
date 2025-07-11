/*~-*/
/*~XSF_LANGUAGE: C/C++*/
/*~I*/
#ifndef INTC_SIGCV_MC1_IM_H
/*~T*/
#define INTC_SIGCV_MC1_IM_H
/*~A*/
/*~+:Module Header*/
/*~T*/
/**************************************************************************

COPYRIGHT (C) $Date: 2024/09/03 09:34:53CEST $
$CompanyInfo: VITESCO TECHNOLOGIES GROUP AG (EXCLUSIVE RIGHTS) $
ALL RIGHTS RESERVED.                                                       
                                                                           
The reproduction, transmission or use of this document or its contents is  
not permitted without express written authority.                           
Offenders will be liable for damages. All rights, including rights created 
by patent grant or registration of a utility model or design, are reserved.
---------------------------------------------------------------------------
 
Purpose: PL import header

$ProjectName: /ES/FS/0G/H0V/pis/0u0/work/app/INTC/intc_sigcv_mc1/i/project.pj $

$Log: intc_sigcv_mc1_im.h  $
Revision 1.2 2024/09/03 09:34:53CEST Zhang Yi (uiv00534) (uiv00534) 
INTC adapt for ecm2_dtsyscansfty
Revision 1.1 2024/09/03 03:20:41CEST Zhang Yi (uiv00534) (uiv00534) 
Initial revision
Member added to project /ES/FS/0G/H0D/0A/bsw/intc/intc_sigcv_mc1/i/project.pj


 ****************************************************************************/

/*~E*/
/*~T*/
/*~T*/
/*common importer*/
#include "ipl_types.h"
#include "ipl_stubs.h"
#include "pl2com_handleids.h"



/*for rx direction*/
#include "ipl_hook_rx_prim.h"
#include "ipl_hook_rx_prim_data.h"
#include "ipl_hook_rx_sec.h"
#include "ipl_hook_rx_sec_data.h"



/*for tx direction*/
#include "ipl_hook_tx_prim.h"
#include "ipl_hook_tx_prim_data.h"
#include "ipl_hook_tx_sec.h"
#include "ipl_hook_tx_sec_data.h"


#include "com_stub.h"
//#include "ps04_emraob_im.h"
#include "ident_decl.h"
#include "ecum_cnf_int_data.h"
#include "ecum_cnf_int.h"




/*~T*/

/*~T*/
#include "gmem.h"
/*~-*/
#endif
/*~E*/
