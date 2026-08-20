#define GE_ORIGINAL_UNIT_PREFIX ge_stubs_
#include "ge_original_host_compat.h"
#include "ge_original_frontend_v6.h"

#include <front.h>
#include <file2.h>
#include <fr.h>
#include <joy.h>
#include <model.h>
#include <music.h>
#include <objecthandler.h>
#include <ramrom.h>
#include <snd.h>

#include <string.h>

extern uint32_t ge_original_host_buttons_pressed;
extern uint32_t ge_original_host_controller_count;
extern void ge_original_host_record_platform_event(
    uint32_t kind, uint32_t operation, uint32_t value0, uint32_t value1,
    uint64_t semantic_hash);

void osSyncPrintf(const char *format, ...)
{
    (void)format;
}

uint32_t ge_original_host_render_words[4096];
uint32_t ge_original_host_render_word_count;
uint32_t ge_original_host_render_command_count;
s32 g_ClockTimer = 1;

static Gfx s_render_buffer[4096];
static ModelFileHeader s_fake_header;
static Model s_fake_model;
static Mtxf s_fake_matrices[4];
static ModelNode *s_fake_switches[8];
static union ModelRwData s_fake_node_data;
static struct sImageTableEntry s_mainfolder_image_table[16];
static struct sImageTableEntry s_crosshair_image_table[2];
static struct sImageTableEntry s_mp_stage_image_table[16];
static struct sImageTableEntry s_mp_charsel_image_table[16];
struct sImageTableEntry *mainfolderimages = s_mainfolder_image_table;
struct sImageTableEntry *crosshairimage = s_crosshair_image_table;
struct sImageTableEntry *mpstageselimages = s_mp_stage_image_table;
struct sImageTableEntry *mpcharselimages = s_mp_charsel_image_table;
static unsigned char s_dynamic_storage[65536];
static size_t s_dynamic_offset;
static Light s_dynamic_lights[8];
static Mtx s_title_matrices[32];

#define GE_ORIGINAL_RESOURCE_HANDLE_CAPACITY 256u
#define GE_ORIGINAL_RESOURCE_HANDLE_TAG UINT32_C(0xd1000000)

typedef struct GEOriginalResourceHandleEntry {
    uintptr_t source_bits;
    uint32_t handle;
} GEOriginalResourceHandleEntry;

static GEOriginalResourceHandleEntry s_resource_handles[
    GE_ORIGINAL_RESOURCE_HANDLE_CAPACITY];
static uint32_t s_resource_handle_count;

static void ge_original_reset_resource_handles(void)
{
    memset(s_resource_handles, 0, sizeof(s_resource_handles));
    s_resource_handle_count = 0u;
}

void ge_original_host_reset_resource_handles_for_test(void)
{
    ge_original_reset_resource_handles();
}

static uint32_t ge_original_resource_handle(const void *value)
{
    uintptr_t source_bits = (uintptr_t)value;
    uint32_t index;

    if (source_bits == 0u) {
        return 0u;
    }
    for (index = 0u; index < s_resource_handle_count; index++) {
        if (s_resource_handles[index].source_bits == source_bits) {
            return s_resource_handles[index].handle;
        }
    }
    if (s_resource_handle_count >= GE_ORIGINAL_RESOURCE_HANDLE_CAPACITY) {
        return UINT32_MAX;
    }
    index = s_resource_handle_count++;
    s_resource_handles[index].source_bits = source_bits;
    s_resource_handles[index].handle = GE_ORIGINAL_RESOURCE_HANDLE_TAG |
        (index + 1u);
    return s_resource_handles[index].handle;
}

static int ge_original_is_resource_handle(uintptr_t value)
{
    return ((uint32_t)value & UINT32_C(0xff000000)) ==
        GE_ORIGINAL_RESOURCE_HANDLE_TAG;
}

/* The source objects use these generated data symbols as inputs.  They are
 * intentionally inert host fixtures; all model/audio work is reported as a
 * source event and never replaced by a procedural draw. */
struct ItemModelFileRecord PitemZ_entries[512];
struct ChrModelFileRecord c_item_entries[256];
ALBank *g_musicSfxBufferPtr;

unsigned char _rarewarelogoSegmentRomStart[64];
unsigned char _rarewarelogoSegmentStart[64];
unsigned char _rarewarelogoSegmentEnd[64];

Gfx dlBasicGeometry[4];
Gfx dlFastPipelineSetup[15];
Gfx s_rareware_display_0[4];
Gfx s_rareware_display_1[4];
Gfx s_rareware_display_2[4];
u8 s_rareware_texture_0[4];
u8 s_rareware_texture_1[4];
Gfx *D_020043E8 = s_rareware_display_0;
Gfx *DL_RAREWARETEXT = s_rareware_display_1;
Gfx *D_02004758 = s_rareware_display_2;
u8 *D_02004FE8 = s_rareware_texture_0;
u8 *D_02005FF0 = s_rareware_texture_1;

struct animation_table_data {
    u8 data[0xffff];
};
static struct animation_table_data s_animation_table;
struct animation_table_data *ptr_animation_table = &s_animation_table;
s32 ANIM_DATA_bond_eye_fire;
/* The source gunbarrel initializer reads only ModelAnimation.unk04 before
 * handing the record to the value-only model sink.  Keep that fixture
 * positive so the unchanged source's start-frame normalization cannot loop
 * forever in the hosted adapter. */
unsigned char ANIM_DATA_bond_eye_walk[16] = { 0, 0, 0, 0, 0, 128, 0, 1 };

static uint64_t ge_original_stub_hash(uint32_t a, uint32_t b)
{
    return (UINT64_C(1469598103934665603) ^ a) * UINT64_C(1099511628211) ^ b;
}

void ge_original_host_prepare_fake_assets(void)
{
    memset(&s_fake_header, 0, sizeof(s_fake_header));
    memset(&s_fake_model, 0, sizeof(s_fake_model));
    memset(s_fake_matrices, 0, sizeof(s_fake_matrices));
    memset(s_fake_switches, 0, sizeof(s_fake_switches));
    memset(&s_fake_node_data, 0, sizeof(s_fake_node_data));
    memset(s_mainfolder_image_table, 0, sizeof(s_mainfolder_image_table));
    memset(s_crosshair_image_table, 0, sizeof(s_crosshair_image_table));
    memset(s_mp_stage_image_table, 0, sizeof(s_mp_stage_image_table));
    memset(s_mp_charsel_image_table, 0, sizeof(s_mp_charsel_image_table));
    for (uint32_t index = 0u; index < 16u; index++) {
        s_mainfolder_image_table[index].width = 32u;
        s_mainfolder_image_table[index].height = 32u;
        s_mainfolder_image_table[index].level = 1u;
        s_mp_stage_image_table[index].width = 32u;
        s_mp_stage_image_table[index].height = 32u;
        s_mp_stage_image_table[index].level = 1u;
        s_mp_charsel_image_table[index].width = 32u;
        s_mp_charsel_image_table[index].height = 32u;
        s_mp_charsel_image_table[index].level = 1u;
    }
    s_crosshair_image_table[0].width = 32u;
    s_crosshair_image_table[0].height = 32u;
    s_crosshair_image_table[0].level = 1u;
    memset(PitemZ_entries, 0, sizeof(PitemZ_entries));
    memset(c_item_entries, 0, sizeof(c_item_entries));
    for (uint32_t index = 0u; index < 512u; index++) {
        PitemZ_entries[index].header = &s_fake_header;
    }
    for (uint32_t index = 0u; index < 256u; index++) {
        c_item_entries[index].header = &s_fake_header;
    }
    s_fake_header.numMatrices = 2;
    s_fake_header.numSwitches = 8;
    s_fake_header.Switches = s_fake_switches;
    s_fake_model.obj = &s_fake_header;
    s_fake_model.render_pos = (RenderPosView *)s_fake_matrices;
    s_fake_model.scale = 1.0f;
    ge_original_host_render_word_count = 0u;
    ge_original_host_render_command_count = 0u;
    ge_original_reset_resource_handles();
    s_dynamic_offset = 0u;
    extern u8 *ptr_logo_and_walletbond_DL;
    ptr_logo_and_walletbond_DL = (u8 *)s_render_buffer;

    extern Mtx *matrixBufferRareLogo0;
    extern Mtx *matrixBufferRareLogo1;
    extern Mtx *matrixBufferRareLogo2;
    extern Mtx *matrixBufferGunbarrel0;
    extern Mtx *matrixBufferGunbarrel1;
    extern Mtx *matrixBufferIntroBackdrop;
    extern Mtx *matrixBufferIntroBond;
    extern Model *chrModelInstance;
    extern Model *gunModelInstance;
    extern Gfx *gunbarrelgfxListPointer;
    matrixBufferRareLogo0 = &s_title_matrices[0];
    matrixBufferRareLogo1 = &s_title_matrices[2];
    matrixBufferRareLogo2 = &s_title_matrices[4];
    matrixBufferGunbarrel0 = &s_title_matrices[6];
    matrixBufferGunbarrel1 = &s_title_matrices[8];
    matrixBufferIntroBackdrop = &s_title_matrices[10];
    matrixBufferIntroBond = &s_title_matrices[12];
    chrModelInstance = &s_fake_model;
    gunModelInstance = &s_fake_model;
    gunbarrelgfxListPointer = s_render_buffer;
}

Model *ge_original_host_fake_model(void) { return &s_fake_model; }

void ge_original_host_set_current_screen(uint32_t screen)
{
    (void)screen;
}

Gfx *ge_original_host_render_buffer(void)
{
    ge_original_host_render_word_count = 0u;
    ge_original_host_render_command_count = 0u;
    ge_original_reset_resource_handles();
    memset(s_render_buffer, 0, sizeof(s_render_buffer));
    return s_render_buffer;
}

u32 ge_original_host_virtual_to_physical(void *value)
{
    return ge_original_resource_handle(value);
}

static int ge_original_pointer_command(uint32_t opcode)
{
    switch (opcode) {
    case 1u:    /* classic G_MTX */
    case 3u:    /* classic G_MOVEMEM */
    case 4u:    /* classic G_VTX */
    case 6u:    /* classic G_DL */
    case 9u:    /* G_SPRITE2D_BASE */
    case 0xddu: /* G_LOAD_UCODE */
    case 0xfdu: /* G_SETTIMG */
    case 0xfeu: /* G_SETZIMG */
    case 0xffu: /* G_SETCIMG */
        return 1;
    default:
        return 0;
    }
}

void ge_original_sanitize_render_words(void)
{
    uint32_t index;

    for (index = 0u; index < ge_original_host_render_command_count; index++) {
        uint32_t opcode = (uint32_t)(s_render_buffer[index].words.w0 >> 24);
        uintptr_t raw;

        raw = s_render_buffer[index].words.w1;
        if (!ge_original_pointer_command(opcode) && raw <= UINT32_MAX) {
            continue;
        }
        if (raw == 0u || ge_original_is_resource_handle(raw)) {
            continue;
        }
        s_render_buffer[index].words.w1 = ge_original_resource_handle(
            (const void *)raw);
    }
}

uint32_t ge_original_host_render_resource_word_safety(void)
{
    uint32_t index;

    for (index = 0u; index < ge_original_host_render_command_count; index++) {
        uint32_t opcode = (uint32_t)(s_render_buffer[index].words.w0 >> 24);
        uintptr_t raw;

        raw = s_render_buffer[index].words.w1;
        if (!ge_original_pointer_command(opcode) && raw <= UINT32_MAX) {
            continue;
        }
        if (raw != 0u && !ge_original_is_resource_handle(raw)) {
            return 0u;
        }
    }
    return 1u;
}

uint64_t ge_original_host_render_command_hash(void)
{
    uint64_t hash = UINT64_C(1469598103934665603);
    uint32_t index;

    for (index = 0u; index < ge_original_host_render_command_count; index++) {
        hash ^= (uint64_t)s_render_buffer[index].words.w0;
        hash *= UINT64_C(1099511628211);
        hash ^= (uint64_t)s_render_buffer[index].words.w1;
        hash *= UINT64_C(1099511628211);
    }
    return hash;
}

uint32_t ge_original_host_render_dialect_flags(void)
{
    uint32_t flags = 0u;
    uint32_t index;

    for (index = 0u; index < ge_original_host_render_command_count; index++) {
        uint32_t opcode = s_render_buffer[index].words.w0 >> 24;
        if (opcode == 6u) {
            flags |= 1u << 0; /* classic GE/F3D G_DL */
        } else if (opcode == 1u) {
            flags |= 1u << 1; /* classic GE/F3D G_MTX */
        } else if (opcode == 4u) {
            flags |= 1u << 2; /* classic GE/F3D G_VTX */
        } else if (opcode == 0xb1u) {
            flags |= 1u << 3; /* GE custom TRI4 */
        }
    }
    return flags;
}


/* Frontend platform/input sinks. */
void viSetFovY(f32 value) { (void)value; }
void viSetAspect(f32 value) { (void)value; }
void viSetZRange(f32 near_value, f32 far_value)
{
    (void)near_value; (void)far_value;
}
void viSetUseZBuf(s32 value) { (void)value; }
void viSetViewSize(s16 x, s16 y) { (void)x; (void)y; }
void viSetViewPosition(s16 left, s16 top) { (void)left; (void)top; }
void viSetBuf(s16 x, s16 y) { (void)x; (void)y; }
void viSetXY(s16 x, s16 y) { (void)x; (void)y; }
void set_cur_player_screen_size(s32 x, s32 y) { (void)x; (void)y; }
void set_cur_player_viewport_size(s32 x, s32 y) { (void)x; (void)y; }
void viSetFrameBuf2(u8 *buf) { (void)buf; }
u8 *viGetFrameBuf2(void) { return NULL; }
Gfx *viSetFillColor(Gfx *gdl, s32 r, s32 g, s32 b)
{ (void)r; (void)g; (void)b; return gdl; }
Gfx *viFillScreen(Gfx *gdl) { return gdl; }
s16 viGetX(void) { return 320; }
s16 viGetY(void) { return 240; }

s8 joyGetControllerCount(void)
{
    return (s8)ge_original_host_controller_count;
}
u16 joyGetButtonsPressedThisFrame(s8 controller, u16 mask)
{
    (void)controller;
    return (u16)(ge_original_host_buttons_pressed & mask);
}
u16 joyGetButtons(s8 controller, u16 mask)
{
    (void)controller;
    return (u16)(ge_original_host_buttons_pressed & mask);
}
s8 joyGetStickX(s8 controller) { (void)controller; return 0; }
s8 joyGetStickY(s8 controller) { (void)controller; return 0; }
s32 joyGetStickXInRange(s8 controller, s32 min, s32 max)
{ (void)controller; (void)min; (void)max; return 0; }
s32 joyGetStickYInRange(s8 controller, s32 min, s32 max)
{ (void)controller; (void)min; (void)max; return 0; }

/* Source lifecycle/audio sinks. */
void fileValidateSaves(void)
{
    ge_original_host_record_platform_event(
        GE_ORIGINAL_FRONTEND_V6_EVENT_SOURCE_GAP, 0x301u, 0u, 0u,
        UINT64_C(0x7361766576616c));
}
void musicTrack1Stop(void)
{
    ge_original_host_record_platform_event(
        GE_ORIGINAL_FRONTEND_V6_EVENT_AUDIO,
        GE_ORIGINAL_FRONTEND_V6_OP_AUDIO_STOP, 0u, 0u,
        ge_original_stub_hash(GE_ORIGINAL_FRONTEND_V6_OP_AUDIO_STOP, 0u));
}
void musicTrack1Play(s32 track)
{
    ge_original_host_record_platform_event(
        GE_ORIGINAL_FRONTEND_V6_EVENT_AUDIO,
        GE_ORIGINAL_FRONTEND_V6_OP_AUDIO_MUSIC, (uint32_t)track, 0u,
        ge_original_stub_hash(GE_ORIGINAL_FRONTEND_V6_OP_AUDIO_MUSIC,
                              (uint32_t)track));
}
u8 *langGet(s32 slotID)
{
    static u8 sourceText[64] = "SOURCE";
    (void)slotID;
    return sourceText;
}
u8 fileGetBondForFolder(u32 folder)
{
    (void)folder;
    return (u8)BOND_BROSNAN;
}
void fileGetHighestStageDifficultyCompletedForFolder(
    s32 foldernum, LEVEL_SOLO_SEQUENCE *levelid, DIFFICULTY *difficulty)
{
    (void)foldernum;
    if (levelid != NULL) { *levelid = SP_LEVEL_DAM; }
    if (difficulty != NULL) { *difficulty = DIFFICULTY_AGENT; }
}
bool fileGetIsCheatUnlocked(save_data *save, s32 cheat)
{
    (void)save;
    (void)cheat;
    return FALSE;
}
save_data *fileGetSaveForFoldernum(u32 folder)
{
    (void)folder;
    return NULL;
}
void fileUpdateBondInCurrentFolder(void) { }
ALSoundState *sndPlaySfx(struct ALBankAlt_s *bank, s16 sound,
                         ALSoundState *pending)
{
    (void)bank; (void)pending;
    ge_original_host_record_platform_event(
        GE_ORIGINAL_FRONTEND_V6_EVENT_AUDIO,
        GE_ORIGINAL_FRONTEND_V6_OP_AUDIO_SFX, (uint32_t)(uint16_t)sound, 0u,
        ge_original_stub_hash(GE_ORIGINAL_FRONTEND_V6_OP_AUDIO_SFX,
                              (uint32_t)(uint16_t)sound));
    return NULL;
}

/* Source model/resource sinks. */
void load_object_fill_header(ModelFileHeader *header, u8 *name, u8 *dst,
                             s32 size, struct texpool *pool)
{
    (void)header; (void)name; (void)dst; (void)size; (void)pool;
    ge_original_host_record_platform_event(
        GE_ORIGINAL_FRONTEND_V6_EVENT_MODEL,
        GE_ORIGINAL_FRONTEND_V6_OP_MODEL_LOAD, 0u, (uint32_t)size,
        ge_original_stub_hash(GE_ORIGINAL_FRONTEND_V6_OP_MODEL_LOAD,
                              (uint32_t)size));
}
void modelCalculateRwDataLen(ModelFileHeader *header) { (void)header; }
Model *modelmgrInstantiateModel(ModelFileHeader *header)
{
    (void)header;
    ge_original_host_record_platform_event(
        GE_ORIGINAL_FRONTEND_V6_EVENT_MODEL,
        GE_ORIGINAL_FRONTEND_V6_OP_MODEL_LOAD, 1u, 0u,
        ge_original_stub_hash(GE_ORIGINAL_FRONTEND_V6_OP_MODEL_LOAD, 1u));
    return &s_fake_model;
}
Model *modelmgrInstantiateModelWithAnim(ModelFileHeader *header)
{
    return modelmgrInstantiateModel(header);
}
void modelSetScale(Model *model, f32 scale)
{
    if (model != NULL) model->scale = scale;
}
void modelSetAnimTranslationScale(Model *model, f32 scale)
{ (void)model; (void)scale; }
void modelSetAnimPlaySpeed(Model *model, f32 speed, f32 arg2)
{ (void)model; (void)speed; (void)arg2; }
void modelSetAnimation(Model *model, ModelAnimation *animation, s32 flip,
                       f32 start, f32 speed, f32 arg5)
{ (void)model; (void)animation; (void)flip; (void)start; (void)speed; (void)arg5; }
void modelUpdateNodeRelations(Model *model) { (void)model; }
void modelSetDistanceDisabled(s32 disabled) { (void)disabled; }
void modelTickAnim(Model *model, s32 delta, s32 arg2)
{ (void)model; (void)delta; (void)arg2; }
void modelSetAnimSpeed(Model *model, f32 speed, f32 time)
{ (void)model; (void)speed; (void)time; }
void setsuboffset(Model *model, coord3d *offset)
{ (void)model; (void)offset; }
void setsubroty(Model *model, f32 angle) { (void)model; (void)angle; }
void clear_model_obj(Model *model)
{
    (void)model;
    ge_original_host_record_platform_event(
        GE_ORIGINAL_FRONTEND_V6_EVENT_MODEL,
        GE_ORIGINAL_FRONTEND_V6_OP_MODEL_RELEASE, 0u, 0u,
        ge_original_stub_hash(GE_ORIGINAL_FRONTEND_V6_OP_MODEL_RELEASE, 0u));
}
void clear_aircraft_model_obj(Model *model) { clear_model_obj(model); }
void subdraw(ModelRenderData *data, Model *model)
{
    (void)model;
    if (data != NULL) {
        ge_original_host_record_platform_event(
            GE_ORIGINAL_FRONTEND_V6_EVENT_MODEL,
            GE_ORIGINAL_FRONTEND_V6_OP_MODEL_DRAW, data->flags, 0u,
            ge_original_stub_hash(GE_ORIGINAL_FRONTEND_V6_OP_MODEL_DRAW,
                                  data->flags));
    }
}
void subcalcmatrices(ModelRenderData *data, Model *model)
{ (void)data; (void)model; }
void instcalcmatrices(ModelRenderData *data, Model *model)
{ (void)data; (void)model; }
Mtxf *modelFindNodeMtx(Model *model, ModelNode *node, s32 index)
{ (void)model; (void)node; (void)index; return s_fake_matrices; }
union ModelRwData *modelGetNodeRwData(Model *model, ModelNode *node)
{ (void)model; (void)node; return &s_fake_node_data; }
void *dynAllocate(s32 size)
{
    size_t requested = size < 0 ? 0u : (size_t)size;
    if (requested > sizeof(s_dynamic_storage) - s_dynamic_offset) {
        return s_dynamic_storage;
    }
    void *result = s_dynamic_storage + s_dynamic_offset;
    s_dynamic_offset += requested;
    return result;
}
Light *dynAllocateLights(s32 count)
{
    (void)count;
    return s_dynamic_lights;
}

/* Matrix/GBI sinks used by source title constructors. */
void matrix_4x4_set_lookat_target(Mtxf *out, f32 a, f32 b, f32 c, f32 d,
                                   f32 e, f32 f, f32 g, f32 h, f32 i, f32 j)
{ (void)a; (void)b; (void)c; (void)d; (void)e; (void)f; (void)g; (void)h; (void)i; (void)j; if (out) memset(out, 0, sizeof(*out)); }
void matrix_4x4_copy(Mtxf *src, Mtxf *dst)
{ if (src != NULL && dst != NULL) memcpy(dst, src, sizeof(*dst)); }
void matrix_4x4_f32_to_s32(f32 src[4][4], s32 dst[4][4])
{ (void)src; if (dst) memset(dst, 0, sizeof(s32) * 16u); }
void matrix_4x4_set_identity(Mtxf *out)
{ if (out) memset(out, 0, sizeof(*out)); }
void matrix_4x4_set_rotation_around_y(f32 angle, Mtxf *out)
{ (void)angle; if (out) memset(out, 0, sizeof(*out)); }
void matrix_4x4_set_rotation_around_z(f32 angle, Mtxf *out)
{ (void)angle; if (out) memset(out, 0, sizeof(*out)); }
void matrix_4x4_multiply_in_place(Mtxf *a, Mtxf *b)
{ (void)a; (void)b; }
void matrix_scalar_multiply(f32 scale, f32 matrix[4][4])
{ (void)scale; (void)matrix; }
void matrix_scalar_multiply_3(f32 scale, f32 matrix[4][4])
{ (void)scale; (void)matrix; }
void guLookAtReflect(Mtx *mtx, LookAt *look, f32 a, f32 b, f32 c, f32 d,
                     f32 e, f32 f, f32 g, f32 h, f32 i)
{ (void)look; (void)a; (void)b; (void)c; (void)d; (void)e; (void)f; (void)g; (void)h; (void)i; if (mtx) memset(mtx, 0, sizeof(*mtx)); }
void guLookAt(Mtx *mtx, f32 a, f32 b, f32 c, f32 d, f32 e, f32 f, f32 g,
              f32 h, f32 i)
{ (void)a; (void)b; (void)c; (void)d; (void)e; (void)f; (void)g; (void)h; (void)i; if (mtx) memset(mtx, 0, sizeof(*mtx)); }
void guPerspective(Mtx *mtx, u16 *norm, f32 a, f32 b, f32 c, f32 d, f32 e)
{ (void)a; (void)b; (void)c; (void)d; (void)e; if (mtx) memset(mtx, 0, sizeof(*mtx)); if (norm) *norm = 1u; }
void guTranslate(Mtx *mtx, f32 a, f32 b, f32 c)
{ (void)a; (void)b; (void)c; if (mtx) memset(mtx, 0, sizeof(*mtx)); }
void guScale(Mtx *mtx, f32 a, f32 b, f32 c)
{ (void)a; (void)b; (void)c; if (mtx) memset(mtx, 0, sizeof(*mtx)); }
void guRotate(Mtx *mtx, f32 a, f32 b, f32 c, f32 d)
{ (void)a; (void)b; (void)c; (void)d; if (mtx) memset(mtx, 0, sizeof(*mtx)); }
u32 osVirtualToPhysical(void *value)
{
    return ge_original_host_virtual_to_physical(value);
}

Gfx *clear_framebuffer_black(Gfx *gdl)
{
    ge_original_host_record_platform_event(
        GE_ORIGINAL_FRONTEND_V6_EVENT_RENDER,
        GE_ORIGINAL_FRONTEND_V6_OP_RENDER_BEGIN, 0u, 0u,
        UINT64_C(0x636c656172626c6b));
    return gdl == NULL ? s_render_buffer : gdl + 1;
}
Gfx *microcode_constructor(Gfx *gdl) { return gdl; }
Gfx *sub_GAME_7F01C1A4(Gfx *gdl) { return gdl; }
Gfx *sub_GAME_7F01CA18(Gfx *gdl) { return gdl; }
Gfx *gunbarrelBloodOverlayDL(Gfx *gdl) { return gdl; }
Gfx *titleRenderFolderMenuBackgroundLines(Gfx *gdl, u8 *image, s32 x,
                                          struct FolderSelectColour *c,
                                          struct FolderSelectColour *d)
{ (void)image; (void)x; (void)c; (void)d; return gdl; }

/* Source title setup sinks. */
void romCopy(void *target, void *source, u32 size)
{ (void)target; (void)source; (void)size; }
void createGunbarrelRenderHole(void *buffer, s32 size)
{ (void)buffer; (void)size; }
void sub_GAME_7F01BFF8(Gfx *a, void *b, s32 c)
{ (void)a; (void)b; (void)c; }
void rle_expand_8bit(u8 *a, u8 *b) { (void)a; (void)b; }
void texInitPool(struct texpool *pool, u8 *buffer, s32 size)
{ (void)pool; (void)buffer; (void)size; }
void drawjointlist(ModelRenderData *data, ModelHitEntry *entry)
{ (void)data; (void)entry; }
ModelHitEntry *sub_GAME_7F06B120(ModelHitEntry *entry, Model *model)
{ (void)model; return entry; }
void sub_GAME_7F06B29C(ModelHitEntry *entry) { (void)entry; }
ModelHitEntry *sub_GAME_7F06BB28(ModelHitEntry *entry) { return entry; }
void sub_GAME_7F06B248(ModelHitEntry *entry) { (void)entry; }
void sub_GAME_7F073FC8(s32 value) { (void)value; }
void subcalcpos(Model *model) { (void)model; }
void mtx4TransformVecInPlace(RenderPosView *render, coord3d *vec)
{ (void)render; (void)vec; }
s32 die_blood_image_routine(s32 mode) { return mode == 1 ? 1 : 0; }
s16 sins(u16 value) { (void)value; return 0; }
f32 floorFloat(f32 value) { return value; }

/* Frontend branches not exercised by this reference route. */
void select_ramrom_to_play(void) { }
Model *setup_chr_instance(enum BODIES body, enum HEADS head,
                          ModelFileHeader *body_header,
                          ModelFileHeader *head_header, s32 arg4)
{
    (void)body;
    (void)head;
    (void)body_header;
    (void)head_header;
    (void)arg4;
    return &s_fake_model;
}
