// sm64audio: renders Mario 64 music and sounds to a WAV file, with the game's own sound engine (from libsm64,
// which carries the decompiled audio code) and the sound data of the player's own ROM.
//
//   sm64audio <rom.z64> <out.wav> <timeline.txt>
//
// The timeline is plain text, one thing per line, times in the game's frames (30 a second):
//   length <frames>                      how long the recording is
//   <frame> music <seqargs>              play_music(0, seqargs, 0); seqargs = priority << 8 | sequence (hex or decimal)
//   <frame> music1 <seqargs>             the same on the second player
//   <frame> stopmusic <seq>              stop_background_music(seq)
//   <frame> fademusic <frames>           fadeout_background_music(0, frames)
//   <frame> sound <NAME>                 play_sound(NAME, gGlobalSoundSource), NAME from audio_defines.h
//   <frame>-<frame> sound <NAME>         the same every frame in between (how the game keeps a sound going)
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

#include "decomp/include/types.h"
#include "decomp/include/audio_defines.h"
#include "decomp/include/seq_ids.h"
#include "decomp/audio/external.h"
#include "load_audio_data.h"
#include "play_sound.h"

#define RATE 32000

struct Named { const char *name; s32 bits; };
#define N(x) { #x, (s32)(x) },
static const struct Named SOUNDS[] = {
    N(SOUND_PEACH_DEAR_MARIO)
    N(SOUND_MENU_THANK_YOU_PLAYING_MY_GAME)
    N(SOUND_PEACH_MARIO)
    N(SOUND_PEACH_POWER_OF_THE_STARS)
    N(SOUND_PEACH_THANKS_TO_YOU)
    N(SOUND_PEACH_THANK_YOU_MARIO)
    N(SOUND_PEACH_SOMETHING_SPECIAL)
    N(SOUND_PEACH_BAKE_A_CAKE)
    N(SOUND_PEACH_FOR_MARIO)
    N(SOUND_PEACH_MARIO2)
    N(SOUND_AIR_LAKITU_FLY_HIGHPRIO)
    N(SOUND_AIR_LAKITU_FLY)
    N(SOUND_ACTION_FLYING_FAST)
    N(SOUND_ACTION_INTRO_UNK45E)
    N(SOUND_ACTION_INTRO_UNK45F)
    N(SOUND_MENU_EXIT_PIPE)
    N(SOUND_MENU_ENTER_PIPE)
    N(SOUND_MENU_CLICK_CHANGE_VIEW)
    N(SOUND_MARIO_YAHOO)
    N(SOUND_MARIO_YAH_WAH_HOO)
    N(SOUND_MARIO_HOOHOO)
    N(SOUND_MARIO_ATTACKED)
    N(SOUND_MARIO_OOOF)
    N(SOUND_MARIO_OOOF2)
    N(SOUND_MARIO_HRMM)
    N(SOUND_MARIO_SO_LONGA_BOWSER)
    N(SOUND_MARIO_HERE_WE_GO)
    { "SOUND_MARIO_WAH", (s32) 0x24018081 },
    { "SOUND_MARIO_HOO", (s32) 0x24028081 },
    N(SOUND_MARIO_HAHA)
    N(SOUND_ACTION_TERRAIN_LANDING)
    N(SOUND_ACTION_TERRAIN_BODY_HIT_GROUND)
    N(SOUND_ACTION_TERRAIN_HEAVY_LANDING)
    N(SOUND_ACTION_HIT_3)
    // Mario's steps, jump and landing in shallow water (terrainSoundAddend SOUND_TERRAIN_WATER << 16)
    { "SOUND_STEP_WATER", (s32) (SOUND_ACTION_TERRAIN_STEP + (SOUND_TERRAIN_WATER << 16)) },
    { "SOUND_JUMP_WATER", (s32) (SOUND_ACTION_TERRAIN_JUMP + (SOUND_TERRAIN_WATER << 16)) },
    { "SOUND_LAND_WATER", (s32) (SOUND_ACTION_TERRAIN_LANDING + (SOUND_TERRAIN_WATER << 16)) },
    { "SOUND_STEP_PLAIN", (s32) (SOUND_ACTION_TERRAIN_STEP) },
    N(SOUND_GENERAL_COIN)
    N(SOUND_MENU_STAR_SOUND)
    // the file select's (menu/file_select.c)
    N(SOUND_MENU_CLICK_FILE_SELECT)
    N(SOUND_MENU_STAR_SOUND_OKEY_DOKEY)
    N(SOUND_MENU_CAMERA_ZOOM_IN)
    N(SOUND_MENU_CAMERA_ZOOM_OUT)
    N(SOUND_MENU_CAMERA_BUZZ)
    N(SOUND_MENU_MESSAGE_APPEAR)
    N(SOUND_MENU_MESSAGE_NEXT_PAGE)
    N(SOUND_MENU_MESSAGE_DISAPPEAR)
    N(SOUND_MARIO_WAAAOOOW)
    // death (mario_actions_cutscene.c common_death_handler, act_death_exit_land; level_update.c WARP_OP_DEATH)
    N(SOUND_MARIO_DYING)
    N(SOUND_MARIO_MAMA_MIA)
    N(SOUND_MENU_BOWSER_LAUGH)
    // the star select (src/menu/star_select.c: an act chosen)
    N(SOUND_MENU_STAR_SOUND_LETS_A_GO)
    // the cap switches (capswitch.inc.c)
    N(SOUND_GENERAL_ACTIVATE_CAP_SWITCH)
    // Mario's face screen (goddard, game/sound_init.c play_menu_sounds, menu/level_select_menu.c intro_default)
    N(SOUND_MENU_PINCH_MARIO_FACE)
    N(SOUND_MENU_LET_GO_MARIO_FACE)
    N(SOUND_MARIO_HELLO)
    // the pop as Mario jumps out of the intro pipe (intro_cutscene_jump_out_of_pipe, not in the Japanese game)
    N(SOUND_ACTION_HIT_3)
    // the castle grounds' ambience (levels/castle_grounds/script.c: bhvAmbientSounds, bhvBirdsSoundLoop x3,
    // bhvWaterfallSoundLoop)
    N(SOUND_AIR_CASTLE_OUTDOORS_AMBIENT)
    N(SOUND_OBJ2_BIRD_CHIRP1)
    N(SOUND_GENERAL2_BIRD_CHIRP2)
    N(SOUND_OBJ_BIRD_CHIRP3)
    N(SOUND_ENV_WATERFALL2)
    N(SOUND_GENERAL_BIRDS_FLY_AWAY)
    // swimming (game/mario_actions_submerged.c): plunge, surfacing, strokes, flutter kick
    N(SOUND_ACTION_UNKNOWN430)
    N(SOUND_ACTION_UNKNOWN431)
    N(SOUND_ACTION_SWIM)
    N(SOUND_ACTION_SWIM_FAST)
    N(SOUND_ACTION_UNKNOWN434)
    N(SOUND_MARIO_DROWNING)
    // the pause screen (game/ingame_menu.c)
    N(SOUND_MENU_PAUSE)
    N(SOUND_MENU_PAUSE_2)
    N(SOUND_MENU_CHANGE_SELECT)
    // coins (game/level_update.c: one per coin as the counter counts up; behaviors/red_coin.inc.c, its pitch
    // going up a step for each red coin) and stomping a goomba (interaction.c bounce_off_object;
    // obj_behaviors_2.c obj_set_squished_action, then the puff of its death, goomba.inc.c's sizes)
    N(SOUND_GENERAL_COIN_WATER)
    N(SOUND_MENU_COLLECT_RED_COIN)
    N(SOUND_ACTION_BOUNCE_OFF_OBJECT)
    N(SOUND_OBJ_STOMPED)
    N(SOUND_OBJ_ENEMY_DEATH_HIGH)
    N(SOUND_OBJ_ENEMY_DEATH_LOW)
    // moving platforms: lifts' hums (elevator.inc.c, platform_on_track.inc.c, rotating_platform.inc.c,
    // checkerboard_platform.inc.c), the seesaw's creak (seesaw_platform.inc.c), a lift setting off and arriving,
    // the ski lift stopping
    N(SOUND_ENV_ELEVATOR1)
    N(SOUND_ENV_ELEVATOR2)
    N(SOUND_ENV_ELEVATOR3)
    N(SOUND_ENV_ELEVATOR4)
    N(SOUND_ENV_BOAT_ROCKING1)
    N(SOUND_GENERAL_QUIET_POUND1)
    N(SOUND_GENERAL_MOVING_PLATFORM_SWITCH)
    N(SOUND_GENERAL_BUTTON_PRESS_2)
    N(SOUND_GENERAL_UNKNOWN4)
    N(SOUND_GENERAL_METAL_POUND)
    N(SOUND_GENERAL_UNKNOWN4_LOWPRIO)
    // the chain chomp (behaviors/chain_chomp.inc.c): its hop, its lunge, the post pounded, the gate smashed
    N(SOUND_GENERAL_CHAIN_CHOMP1)
    N(SOUND_GENERAL_CHAIN_CHOMP2)
    N(SOUND_GENERAL_POUND_WOOD_POST)
    N(SOUND_GENERAL_WALL_EXPLOSION)
    // bob-ombs (behaviors/bobomb.inc.c, explosion.inc.c) and King Bob-omb (king_bobomb.inc.c); a star appearing
    N(SOUND_OBJ_BOBOMB_WALK)
    N(SOUND_AIR_BOBOMB_LIT_FUSE)
    N(SOUND_GENERAL2_BOBOMB_EXPLOSION)
    N(SOUND_OBJ_KING_BOBOMB)
    N(SOUND_OBJ2_KING_BOBOMB_DAMAGE)
    N(SOUND_OBJ_KING_BOBOMB_JUMP)
    N(SOUND_OBJ_POUNDING1_HIGHPRIO)
    N(SOUND_OBJ_KING_WHOMP_DEATH)
    N(SOUND_OBJ_UNKNOWN3)
    N(SOUND_OBJ_UNKNOWN4)
    N(SOUND_GENERAL_STAR_APPEARS)
    // the game at large: stars, 1-ups, hearts, doors, warps, boxes, Bowser, switches
    N(SOUND_GENERAL_COLLECT_1UP)
    N(SOUND_GENERAL_HEART_SPIN)
    N(SOUND_GENERAL_OPEN_WOOD_DOOR)
    N(SOUND_GENERAL_CLOSE_WOOD_DOOR)
    N(SOUND_GENERAL_OPEN_IRON_DOOR)
    N(SOUND_GENERAL_CLOSE_IRON_DOOR)
    N(SOUND_GENERAL_STAR_DOOR_OPEN)
    N(SOUND_GENERAL_SHORT_STAR)
    N(SOUND_GENERAL_DOOR_INSERT_KEY)
    N(SOUND_GENERAL_DOOR_TURN_KEY)
    N(SOUND_GENERAL_STAR_DOOR_CLOSE)
    N(SOUND_ACTION_TELEPORT)
    N(SOUND_GENERAL_PAINTING_EJECT)
    N(SOUND_GENERAL_BREAK_BOX)
    N(SOUND_GENERAL_BOX_LANDING)
    N(SOUND_GENERAL2_RIGHT_ANSWER)
    N(SOUND_MENU_COLLECT_SECRET)
    N(SOUND_GENERAL_BIG_POUND)
    N(SOUND_GENERAL_BOWSER_BOMB_EXPLOSION)
    N(SOUND_OBJ_BOWSER_LAUGH)
    N(SOUND_OBJ2_BOWSER_ROAR)
    N(SOUND_OBJ_BOWSER_TAIL_PICKUP)
    N(SOUND_OBJ_BOWSER_DEFEATED)
    N(SOUND_OBJ2_BOWSER_TELEPORT)
    N(SOUND_OBJ_BOWSER_WALK)
    N(SOUND_OBJ_BOWSER_INTRO_LAUGH)
    N(SOUND_GENERAL_CAGE_OPEN)
    N(SOUND_GENERAL_WATER_LEVEL_TRIG)
    N(SOUND_GENERAL_ACTIVATE_CAP_SWITCH)
    N(SOUND_GENERAL2_PURPLE_SWITCH)
    N(SOUND_GENERAL_CANNON_UP)
    N(SOUND_GENERAL_EXPLOSION6)
    N(SOUND_ENV_MOVINGSAND)
    N(SOUND_ENV_DRONING1)
    // enemies (behaviors/*.inc.c)
    N(SOUND_OBJ_WHOMP_LOWPRIO)
    N(SOUND_GENERAL2_SPINDEL_ROLL)
    N(SOUND_ENV_MERRY_GO_ROUND_CREAKING)
    N(SOUND_GENERAL_BUTTON_PRESS_2_LOWPRIO)
    N(SOUND_GENERAL_ELEVATOR_MOVE_2)
    N(SOUND_OBJ2_BOWSER_PUZZLE_PIECE_MOVE)
    N(SOUND_GENERAL_BOAT_TILT1)
    N(SOUND_GENERAL_BOAT_TILT2)
    N(SOUND_MARIO_COUGHING1)
    N(SOUND_ENV_UNKNOWN2)
    N(SOUND_OBJ_SNOWMAN_BOUNCE)
    N(SOUND_OBJ_SNOWMAN_EXPLODE)
    N(SOUND_GENERAL_UNK46)
    N(SOUND_ENV_WATER)
    N(SOUND_GENERAL_GRINDEL_ROLL)
    N(SOUND_OBJ_SOMETHING_LANDING)
    N(SOUND_OBJ_WATER_BOMB_BOUNCING)
    N(SOUND_OBJ_DIVING_IN_WATER)
    { "SOUND_ENV_MOVING_BIG_PLATFORM", (s32) 0x41150001 },
    { "SOUND_GENERAL2_BOWSER_EXPLODE", (s32) 0x80600081 },
    { "SOUND_GENERAL2_BOWSER_KEY", (s32) 0x80610081 },
    { "SOUND_GENERAL_GRAND_STAR", (s32) 0x30730081 },
    { "SOUND_GENERAL_KEY_BOUNCE", (s32) 0x38378081 },
    { "SOUND_GENERAL_GRAND_STAR_JUMP", (s32) 0x30740081 },
    { "SOUND_GENERAL2_STAR_APPEARS", (s32) 0x8057FF91 },
    { "SOUND_GENERAL2_PYRAMID_TOP_SPIN", (s32) 0x814BE081 },
    { "SOUND_GENERAL2_PYRAMID_TOP_EXPLOSION", (s32) 0x814CF081 },
    N(SOUND_OBJ_BOWSER_INHALING)
    N(SOUND_AIR_BOWSER_SPIT_FIRE)
    N(SOUND_MARIO_ON_FIRE)
    N(SOUND_GENERAL_VANISH_SFX)
    N(SOUND_GENERAL_BOING2_LOWPRIO)
    N(SOUND_GENERAL_SPLATTERING)
    N(SOUND_GENERAL_BOAT_ROCK)
    N(SOUND_AIR_BLOW_WIND)
    N(SOUND_GENERAL_BOWSER_PLATFORM_2)
    N(SOUND_ENV_WIND1)
    N(SOUND_ENV_WIND2)
    N(SOUND_GENERAL_SWISH_WATER)
    N(SOUND_OBJ_EEL_2)
    N(SOUND_MENU_YOSHI_GAIN_LIVES)
    N(SOUND_MENU_MARIO_CASTLE_WARP2)
    N(SOUND_MARIO_PANTING)
    N(SOUND_OBJ_SUSHI_SHARK_WATER_SOUND)
    N(SOUND_OBJ_BUBBA_CHOMP)
    N(SOUND_ACTION_HIT_2)
    N(SOUND_OBJ_SNOW_SAND1)
    N(SOUND_OBJ_SNOW_SAND2)
    N(SOUND_OBJ_MR_BLIZZARD_ALERT)
    N(SOUND_OBJ_WALKING_WATER)
    N(SOUND_OBJ_KLEPTO1)
    N(SOUND_OBJ_KLEPTO2)
    N(SOUND_MARIO_UH)
    N(SOUND_MARIO_UH2)
    N(SOUND_MARIO_EEUH)
    N(SOUND_MARIO_PUNCH_YAH)
    N(SOUND_MARIO_PUNCH_WAH)
    N(SOUND_MARIO_PUNCH_HOO)
    N(SOUND_MARIO_DOH)
    N(SOUND_MARIO_WHOA)
    N(SOUND_ACTION_BONK)
    N(SOUND_ACTION_CLIMB_UP_POLE)
    N(SOUND_ACTION_CLIMB_UP_TREE)
    N(SOUND_MOVING_SLIDE_DOWN_POLE)
    N(SOUND_MOVING_SLIDE_DOWN_TREE)
    N(SOUND_OBJ2_EYEROK_SOUND_LONG)
    N(SOUND_OBJ2_EYEROK_SOUND_SHORT)
    N(SOUND_OBJ_EYEROK_SHOW_EYE)
    N(SOUND_OBJ_EYEROK_EXPLODE)
    N(SOUND_OBJ_CANNON1)
    N(SOUND_ENV_WATER_DRAIN)
    N(SOUND_GENERAL_CLAM_SHELL1)
    N(SOUND_GENERAL_OPEN_CHEST)
    N(SOUND_OBJ2_BABY_PENGUIN_YELL)
    N(SOUND_GENERAL_HAUNTED_CHAIR)
    N(SOUND_GENERAL_HAUNTED_CHAIR_MOVE)
    N(SOUND_OBJ_MAD_PIANO_CHOMPING)
    N(SOUND_OBJ_KOOPA_THE_QUICK_WALK)
    N(SOUND_GENERAL_RACE_GUN_SHOT)
    N(SOUND_GENERAL_DONUT_PLATFORM_EXPLOSION)
    N(SOUND_OBJ_POUNDING_CANNON)
    N(SOUND_GENERAL_BIG_CLOCK)
    N(SOUND_GENERAL_CASTLE_TRAP_OPEN)
    N(SOUND_GENERAL_POUND_ROCK)
    N(SOUND_GENERAL_PLATFORM)
    N(SOUND_GENERAL_UNKNOWN1_2)
    N(SOUND_GENERAL_QUIET_POUND2)
    N(SOUND_OBJ_UNKNOWN2)
    N(SOUND_ENV_METAL_BOX_PUSH)
    N(SOUND_GENERAL_CLAM_SHELL3)
    N(SOUND_GENERAL_CLAM_SHELL2)
    N(SOUND_GENERAL2_SWITCH_TICK_SLOW)
    N(SOUND_GENERAL2_SWITCH_TICK_FAST)
    N(SOUND_GENERAL_SWITCH_DOOR_OPEN)
    N(SOUND_GENERAL2_1UP_APPEAR)
    N(SOUND_GENERAL2_ROTATING_BLOCK_ALERT)
    N(SOUND_GENERAL2_ROTATING_BLOCK_CLICK)
    N(SOUND_GENERAL_PENDULUM_SWING)
    N(SOUND_OBJ_POUNDING1)
    N(SOUND_OBJ2_WHOMP_SOUND_SHORT)
    N(SOUND_OBJ2_SCUTTLEBUG_ALERT)
    N(SOUND_OBJ2_SCUTTLEBUG_WALK)
    N(SOUND_OBJ_DYING_ENEMY1)
    N(SOUND_OBJ_GOOMBA_ALERT)
    N(SOUND_OBJ2_BULLY_ATTACKED)
    N(SOUND_OBJ2_LARGE_BULLY_ATTACKED)
    N(SOUND_OBJ_BULLY_WALK)
    N(SOUND_OBJ_BULLY_WALKING)
    N(SOUND_OBJ_THWOMP)
    N(SOUND_AIR_CHUCKYA_MOVE)
    N(SOUND_OBJ_CHUCKYA_DEATH)
    N(SOUND_AIR_HEAVEHO_MOVE)
    N(SOUND_OBJ_HEAVEHO_TOSSED)
    N(SOUND_OBJ_KOOPA_DAMAGE)
    N(SOUND_OBJ_KOOPA_FLYGUY_DEATH)
    N(SOUND_OBJ_KOOPA_WALK)
    N(SOUND_OBJ_POKEY_DEATH)
    N(SOUND_OBJ_UKIKI_CHATTER_IDLE)
    N(SOUND_OBJ_UKIKI_CHATTER_SHORT)
    N(SOUND_OBJ2_MONTY_MOLE_APPEAR)
    N(SOUND_OBJ_MONTY_MOLE_ATTACK)
    N(SOUND_OBJ_SNOWMAN_BOUNCE)
    N(SOUND_OBJ_SNOWMAN_EXPLODE)
    N(SOUND_GENERAL_UNK46)
    N(SOUND_ENV_WATER)
    N(SOUND_GENERAL_GRINDEL_ROLL)
    N(SOUND_OBJ_SOMETHING_LANDING)
    N(SOUND_OBJ_WATER_BOMB_BOUNCING)
    N(SOUND_OBJ_DIVING_IN_WATER)
    N(SOUND_GENERAL_VANISH_SFX)
    N(SOUND_GENERAL_BOING2_LOWPRIO)
    N(SOUND_GENERAL_SPLATTERING)
    N(SOUND_OBJ_SKEETER_WALK)
    N(SOUND_OBJ_SNUFIT_SKEETER_DEATH)
    N(SOUND_OBJ_FLAME_BLOWN)
    N(SOUND_OBJ2_SWOOP)
    N(SOUND_OBJ_SWOOP_DEATH)
    N(SOUND_OBJ_SNUFIT_SHOOT)
    N(SOUND_OBJ_KLEPTO1)
    N(SOUND_OBJ_KLEPTO2)
    N(SOUND_OBJ_BOO_LAUGH_LONG)
    N(SOUND_OBJ_BOO_LAUGH_SHORT)
    N(SOUND_OBJ_BOO_BOUNCE_TOP)
    N(SOUND_AIR_AMP_BUZZ)
    N(SOUND_MOVING_SHOCKED)
    N(SOUND_OBJ2_PIRANHA_PLANT_BITE)
    N(SOUND_OBJ2_PIRANHA_PLANT_DYING)
    N(SOUND_OBJ_ENEMY_DEFEAT_SHRINK)
    N(SOUND_OBJ_PIRANHA_PLANT_APPEAR)
    N(SOUND_OBJ_EVIL_LAKITU_THROW)
    N(SOUND_OBJ2_MRI_SPINNING)
    N(SOUND_OBJ_MRI_DEATH)
    N(SOUND_OBJ_MRI_SHOOT)
    N(SOUND_AIR_BLOW_FIRE)
    N(SOUND_OBJ_DEFAULT_DEATH)
    N(SOUND_OBJ_BULLY_EXPLODE_2)
    N(SOUND_GENERAL_COIN_SPURT)
    N(SOUND_OBJ_SPINY_UNK59)
    N(SOUND_AIR_BOWSER_SPIT_FIRE)
    N(SOUND_OBJ_BOWSER_SPINNING)
    N(SOUND_OBJ_BIG_PENGUIN_WALK)
    N(SOUND_AIR_ROUGH_SLIDE)
    N(SOUND_ENV_SINK_QUICKSAND)
    N(SOUND_OBJ_BIG_PENGUIN_YELL)
    N(SOUND_OBJ_KOOPA_TALK)
    N(SOUND_OBJ_BOBOMB_BUDDY_TALK)
    N(SOUND_OBJ2_BOSS_DIALOG_GRUNT)
    N(SOUND_OBJ_WIGGLER_TALK)
    N(SOUND_OBJ_WIGGLER_ATTACKED)
    N(SOUND_OBJ_WIGGLER_JUMP)
    N(SOUND_OBJ_WIGGLER_LOW_PITCH)
    N(SOUND_OBJ_WIGGLER_HIGH_PITCH)
    N(SOUND_GENERAL_YOSHI_TALK)
    N(SOUND_ACTION_SPIN)
    N(SOUND_ACTION_SHRINK_INTO_BBH)
    { NULL, 0 }
};

// NAME, or NAME+number (added to its bits: SOUND_MENU_COLLECT_RED_COIN+0x30000 is the fourth red coin's pitch)
static s32 sound_named(const char *full) {
    char name[128];
    s32 add = 0;
    strncpy(name, full, sizeof name - 1);
    name[sizeof name - 1] = 0;
    char *plus = strchr(name, '+');
    if (plus) { *plus = 0; add = (s32) strtol(plus + 1, NULL, 0); }
    for (int i = 0; SOUNDS[i].name; i++) if (strcmp(SOUNDS[i].name, name) == 0) return SOUNDS[i].bits + add;
    fprintf(stderr, "unknown sound %s\n", name);
    exit(2);
}

struct Event { int from, to; int kind; long arg; };
enum { MUSIC, MUSIC1, STOPMUSIC, FADEMUSIC, SOUND };

static void put32(FILE *f, uint32_t v) { fputc(v & 255, f); fputc((v >> 8) & 255, f); fputc((v >> 16) & 255, f); fputc((v >> 24) & 255, f); }
static void put16(FILE *f, uint16_t v) { fputc(v & 255, f); fputc((v >> 8) & 255, f); }

int main(int argc, char **argv) {
    if (argc < 4) { fprintf(stderr, "usage: sm64audio <rom.z64> <out.wav> <timeline.txt>\n"); return 1; }
    FILE *rf = fopen(argv[1], "rb");
    if (!rf) { fprintf(stderr, "no rom %s\n", argv[1]); return 1; }
    uint8_t *rom = malloc(0x800000);
    size_t got = fread(rom, 1, 0x800000, rf);
    fclose(rf);
    if (got < 0x7D0000) { fprintf(stderr, "rom too short (%zu)\n", got); return 1; }

    struct Event ev[512];
    int nev = 0, length = 30 * 10;
    FILE *tf = fopen(argv[3], "r");
    if (!tf) { fprintf(stderr, "no timeline %s\n", argv[3]); return 1; }
    char line[256];
    while (fgets(line, sizeof line, tf)) {
        char a[64], b[64], c[128];
        int n = sscanf(line, "%63s %63s %127s", a, b, c);
        if (n < 2 || a[0] == '#') continue;
        if (strcmp(a, "length") == 0) { length = atoi(b); continue; }
        if (n < 3 || nev >= 512) continue;
        struct Event *e = &ev[nev++];
        char *dash = strchr(a, '-');
        e->from = atoi(a);
        e->to = dash ? atoi(dash + 1) : e->from;
        if (strcmp(b, "music") == 0) { e->kind = MUSIC; e->arg = strtol(c, NULL, 0); }
        else if (strcmp(b, "music1") == 0) { e->kind = MUSIC1; e->arg = strtol(c, NULL, 0); }
        else if (strcmp(b, "stopmusic") == 0) { e->kind = STOPMUSIC; e->arg = strtol(c, NULL, 0); }
        else if (strcmp(b, "fademusic") == 0) { e->kind = FADEMUSIC; e->arg = strtol(c, NULL, 0); }
        else if (strcmp(b, "sound") == 0) { e->kind = SOUND; e->arg = sound_named(c); }
        else { fprintf(stderr, "unknown line: %s", line); nev--; }
    }
    fclose(tf);

    load_audio_banks(rom);

    FILE *out = fopen(argv[2], "wb");
    if (!out) { fprintf(stderr, "cannot write %s\n", argv[2]); return 1; }
    fwrite("RIFF\0\0\0\0WAVEfmt ", 1, 16, out);
    put32(out, 16); put16(out, 1); put16(out, 2); put32(out, RATE); put32(out, RATE * 4); put16(out, 4); put16(out, 16);
    fwrite("data\0\0\0\0", 1, 8, out);

    static s16 buf[2 * 2 * 544];
    uint64_t made = 0;
    for (int frame = 0; frame < length; frame++) {
        for (int i = 0; i < nev; i++) {
            struct Event *e = &ev[i];
            if (frame < e->from || frame > e->to) continue;
            switch (e->kind) {
                case MUSIC: play_music(0, (u16) e->arg, 0); break;
                case MUSIC1: play_music(1, (u16) e->arg, 0); break;
                case STOPMUSIC: stop_background_music((u16) e->arg); break;
                case FADEMUSIC: fadeout_background_music(0, (u16) e->arg); break;
                case SOUND: play_sound((u32) e->arg, gGlobalSoundSource); break;
            }
        }
        update_game_sound();
        // two buffers a frame, 544 or 528 samples each, so that 30 frames make 32000 samples
        uint64_t want = (uint64_t)(frame + 1) * RATE / 30;
        u32 n = (made + 2 * 544 <= want) ? 544 : 528;
        for (int i = 0; i < 2; i++) create_next_audio_buffer(buf + i * 2 * n, n);
        fwrite(buf, sizeof(s16), 2 * 2 * n, out);
        made += 2 * n;
    }
    uint32_t bytes = (uint32_t)(made * 4);
    fseek(out, 4, SEEK_SET); put32(out, 36 + bytes);
    fseek(out, 40, SEEK_SET); put32(out, bytes);
    fclose(out);
    printf("wrote %s: %.2f s\n", argv[2], made / (double) RATE);
    return 0;
}
