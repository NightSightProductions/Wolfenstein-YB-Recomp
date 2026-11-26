// Imports specific to Wolfenstein: Youngblood.
#include <stdlib.h>
#include <string.h>
#include "rt.h"

// amd_ags_x64.dll (AMD GPU Services 5.x). The engine uses it for AMD-only driver extensions (shader intrinsics,
// crossfire); on a Mac there is no AMD driver, so agsInit fails the way it does on an NVIDIA/Intel PC and the
// engine carries on without it.
//   AGSReturnCode agsInit(AGSContext **context, const AGSConfiguration *config, AGSGPUInfo *gpuInfo)
#define AGS_SUCCESS 0
#define AGS_ERROR_LEGACY_DRIVER 7   // AGS 5: "returned if driver doesn't support AGS"
void youngblood_cloud_log(void);
void I_amd_ags_x64_dll_agsInit(CPU *c) {
    // one of the first calls after the log is open: the save-folder setup (cloud_youngblood.c, which runs before the log
    // exists) reports here
    youngblood_cloud_log();
    static int logged;
    if (!logged++) rt_log("[ags] agsInit: no AMD driver\n");
    if (A0) *(uint64_t *)PTR(A0) = 0;
    RET(AGS_ERROR_LEGACY_DRIVER);
}
void I_amd_ags_x64_dll_agsDeInit(CPU *c) { RET(AGS_SUCCESS); }

// GfeSDK.dll (NVIDIA GeForce Experience: Highlights video capture). There is no GeForce Experience on a Mac:
// NVGSDK_Create fails as it does on a PC without it, and the game turns the feature off.
#define NVGSDK_ERR_GENERIC (-1001)
void I_gfesdk_dll_NVGSDK_Create(CPU *c) {
    static int logged;
    if (!logged++) rt_log("[gfe] NVGSDK_Create: no GeForce Experience\n");
    if (A0) *(uint64_t *)PTR(A0) = 0;
    RET((uint32_t)NVGSDK_ERR_GENERIC);
}
void I_gfesdk_dll_NVGSDK_Release(CPU *c) { RET((uint32_t)NVGSDK_ERR_GENERIC); }
void I_gfesdk_dll_NVGSDK_Poll(CPU *c) { RET((uint32_t)NVGSDK_ERR_GENERIC); }
void I_gfesdk_dll_NVGSDK_RequestPermissionsAsync(CPU *c) {}
void I_gfesdk_dll_NVGSDK_Highlights_ConfigureAsync(CPU *c) {}
void I_gfesdk_dll_NVGSDK_Highlights_OpenGroupAsync(CPU *c) {}
void I_gfesdk_dll_NVGSDK_Highlights_CloseGroupAsync(CPU *c) {}
void I_gfesdk_dll_NVGSDK_Highlights_SetVideoHighlightAsync(CPU *c) {}
void I_gfesdk_dll_NVGSDK_Highlights_SetScreenshotHighlightAsync(CPU *c) {}
void I_gfesdk_dll_NVGSDK_Highlights_GetNumberOfHighlightsAsync(CPU *c) {}
void I_gfesdk_dll_NVGSDK_Highlights_OpenSummaryAsync(CPU *c) {}

// msdmo.dll: DMO_MEDIA_TYPE { majortype 0, subtype 16, bFixedSizeSamples 32, bTemporalCompression 36,
// lSampleSize 40, formattype 44, pUnk 64, cbFormat 72, pbFormat 80 }
void I_msdmo_dll_MoInitMediaType(CPU *c) {
    uint8_t *mt = PTR(A0); uint32_t n = (uint32_t)A1;
    memset(mt, 0, 88);
    *(uint32_t *)(mt + 72) = n;
    if (n) { void *f = calloc(1, n); if (!f) { RET(0x8007000E); return; } *(uint64_t *)(mt + 80) = G(f); }   // E_OUTOFMEMORY
    RET(0);
}
void I_msdmo_dll_MoFreeMediaType(CPU *c) {
    uint8_t *mt = PTR(A0);
    free(PTR(*(uint64_t *)(mt + 80))); *(uint64_t *)(mt + 80) = 0; *(uint32_t *)(mt + 72) = 0;
    RET(0);
}
