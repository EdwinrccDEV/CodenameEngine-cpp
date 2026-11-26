// ============================================================================
// Port de assets/songs/sustainAnim.hx
//
// Bloquea la animacion al mantener una nota y la remata en el ultimo sustain.
// Usa optional chaining (`?.`) y asignaciones encadenadas, que HScript soporta.
// ============================================================================

void onNoteHit(Dynamic e) {
    if (e->note->isSustainNote) {
        e->preventAnim();

        for (int i = 0; i < e->characters.length; i++) {
            e->characters[i]->lastAnimContext = "LOCK";
            if (e->note->nextNote == nullptr || !e->note->nextNote->isSustainNote) {
                e->characters[i]->lastHit = Conductor::songPosition + 30;
                e->characters[i]->lastAnimContext = "SING";
            }
        }
    }
}

void onPlayerMiss(Dynamic e) {
    if (e->note?.isSustainNote) {
        for (int i = 0; i < e->characters.length; i++) {
            e->characters[i]->lastAnimContext = "LOCK";
            if (e->note->nextNote == nullptr || !e->note->nextNote->isSustainNote)
                e->characters[i]->lastAnimContext = "MISS";
        }
        e->preventAnim();
        e->preventVocalsUnmute();
        e->healthGain = e->misses = e->score = e->accuracy = 0;
        e->preventMissSound();
    }
}
