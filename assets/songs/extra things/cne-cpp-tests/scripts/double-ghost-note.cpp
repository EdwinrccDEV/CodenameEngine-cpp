#include "funkin/objects/Character.hpp"
#include "funkin/backend/utils/Note.hpp"

bool disableGhosts = false;

std::map<int, Dynamic> data = {};

void postCreate() {
    for (auto& sl : strumLines->members) {
        data[strumLines->members.indexOf(sl)] = {
            lastNote: {
                time: -9999,
                id: -1
            }
        };
    }
}

void onNoteHit(NoteHitEvent* event) {
    if (event->note->isSustainNote) return;

    auto target = data[strumLines->members.indexOf(event->note->strumLine)];
    auto doDouble = (event->note->strumTime - target->lastNote->time) <= 2
        && event->note->noteData != target->lastNote->id;

    target->lastNote->time = event->note->strumTime;
    target->lastNote->id = event->note->noteData;

    if (doDouble && !disableGhosts) {
        for (auto& character : event->characters) {
            if (character->visible) doGhostAnim(character, event);
        }
    }
}

Character* doGhostAnim(Character* chr, NoteHitEvent* e) {
    Character* trail = new Character(chr->x, chr->y, chr->curCharacter, chr->isPlayer);
    trail->color = chr->iconColor;
    trail->alpha = chr->alpha * 0.85;
    trail->scale.set(chr->scale.x, chr->scale.y);
    trail->flipX = chr->flipX;
    trail->visible = chr->visible;
    trail->shader = chr->shader;

    insert(members.indexOf(chr), trail);
    trail->playAnim(chr->getAnimName(), false, "LOCK");

    FlxTween::tween(trail, {alpha: 0}, 0.55).onComplete = [trail]() {
        trail->kill();
        remove(trail, true);
    };

    switch (e->note->noteData) {
        case 0:
            FlxTween::tween(trail, {x: chr->x + 60}, 1.1, {ease: FlxEase::sineOut});
            break;
        case 1:
            FlxTween::tween(trail, {y: chr->y - 60, x: chr->x + 60}, 1.1, {ease: FlxEase::sineOut});
            break;
        case 2:
            FlxTween::tween(trail, {y: chr->y - 60}, 1.1, {ease: FlxEase::sineOut});
            break;
        case 3:
            FlxTween::tween(trail, {x: chr->x - 60}, 1.1, {ease: FlxEase::sineOut});
            break;
    }

    trail->holdTime = 9999999;
    return trail;
}
