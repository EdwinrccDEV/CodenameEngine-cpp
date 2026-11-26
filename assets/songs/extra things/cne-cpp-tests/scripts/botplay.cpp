// ============================================================================
// Port de assets/songs/Botplay.hx
//
// Unica diferencia: aqui no existe `allowGitaroo` (es de otro fork), asi que el
// toggle no toca esa variable.
// ============================================================================

#include "flixel/text/FlxTextBorderStyle.hpp"
#include "funkin/backend/utils/Note.hpp"

bool botplay = false;
bool blockInputs = true;

FlxText* btpt = nullptr;

void postCreate() {
    btpt = new FlxText(18, 633, 0, "Botplay: off", 10);
    btpt->setFormat(Paths::font("freeplay.ttf"), 15, FlxColor::WHITE, "center");
    add(btpt);
    btpt->camera = camHUD;
    btpt->alpha = 1;
    btpt->borderStyle = FlxTextBorderStyle::OUTLINE;
    btpt->borderSize = 1;
    btpt->borderColor = FlxColor::BLACK;
    btpt->visible = false;

    strumLines->forEach([&](Dynamic strum) {
        if (strum->cpu) return;
        strum->onNoteUpdate->add([&](Dynamic e) { updateNote(e); });
    });
}

void update(float elapsed) {
    if (FlxG::keys->justPressed->B) {
        botplay = !botplay;
        canDie = !botplay;
        btpt->text = botplay ? "Botplay: on" : "Botplay: off";
    }

    playerStrums->forEach([&](Dynamic strum) { strum->cpu = botplay; });
}

void onInputUpdate(Dynamic event) {
    if (blockInputs && botplay) event->cancel();
}

void updateNote(Dynamic e) {
    if (!botplay) return;

    auto daNote = e->note;
    if (!daNote->avoid && !daNote->wasGoodHit && daNote->strumTime < Conductor::songPosition)
        PlayState::instance->goodNoteHit(daNote->strumLine, daNote);
}

void onNoteHit(Dynamic e) {
    if (e->note->strumLine == strumLines->members[1] && !e->note->isSustainNote) {
        e->showSplash = true;
    }
}
