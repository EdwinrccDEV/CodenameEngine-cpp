// ============================================================================
// Port de assets/songs/stickerTransition.hx
//
// Cambia el script de transicion que usa el motor al pausar y al perder.
// ============================================================================

#include "funkin/backend/MusicBeatTransition.hpp"

void onGamePause(Dynamic event) {
    MusicBeatTransition::script = "data/stickerTransition.hx";
}

void onSubstateClose(Dynamic event) {
    if (!Std::isOfType(subState, MusicBeatTransition) && paused) {
        MusicBeatTransition::script = "";
    }
}

void onGameOver(Dynamic event) {
    MusicBeatTransition::script = "data/stickerTransition.hx";
}
