// ============================================================================
// Recreación en C++ de assets/songs/extra things/compotandere/scripts/Camera Scrolling.hx
// Usa scroll-helpers.hpp (mismo folder) para mostrar los scripts multi-archivo.
// ============================================================================

#include "scroll-helpers.hpp"

int offsetSing = 60;
bool isScroll = true;
bool isForcedCam = false;

void postUpdate(float elapsed) {
    Character* chr = strumLines->members[curCameraTarget].characters[0];

    if (!isScroll) return;

    switch (chr->getAnimName()) {
        case "singLEFT":
            doScrollStuff(-offsetSing, 0, 1);
            break;
        case "singDOWN":
            doScrollStuff(0, offsetSing, 0);
            break;
        case "singUP":
            doScrollStuff(0, -offsetSing, 0);
            break;
        case "singRIGHT":
            doScrollStuff(offsetSing, 0, -1);
            break;
        case "idle":
        case "singLEFTmiss":
        case "singDOWNmiss":
        case "singUPmiss":
        case "singRIGHTmiss":
            doScrollStuff(0, 0, 0);
            break;
    }
}

void doScrollStuff(float x, float y, float angle) {
    FlxG::camera->targetOffset.set(x, y);
    FlxG::camera->angle = FlxMath::lerp(FlxG::camera->angle, angle, scrollLerpSpeed(camera, offsetSing));
}

void onCameraMove(CameraMoveEvent* e) {
    if (isForcedCam) {
        e->cancelled = true;
    } else {
        e->cancelled = false;
    }
}
