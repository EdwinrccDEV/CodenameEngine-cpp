// ============================================================================
// Recreación en C++ de assets/songs/extra things/compotandere/scripts/events.hx
//
// Para usarlo: copia este archivo a
//   assets/songs/extra things/compotandere/scripts/events.cpp
// y quita (o renombra) events.hx, porque si no los dos scripts se ejecutan.
// ============================================================================

#include "funkin/backend/utils/AudioAnalyzer.hpp"
#include "flixel/util/FlxGradient.hpp"

// ---------------------------------------------------------------- variables

AudioAnalyzer* analyzer = nullptr;
std::vector<std::vector<float>> audioPoints;

int numberOfBars = 64;
float milliseconds = 50;
int exponent = 2;
float startY = 720;

int barColor1 = 0xFFaa00ff;
int barColor2 = 0xFF00E5FF;

float length = 0;
int secondCount = 0;

FlxTypedGroup<FlxSprite>* audioBarsTop = nullptr;
FlxTypedGroup<FlxSprite>* audioBarsBottom = nullptr;
FlxSprite* mySquare = nullptr;
bool isEpicPartActive = false;

FlxSprite* blackSquare = new FlxSprite(0, 0);
FlxSprite* whitesquare = new FlxSprite(-5000, -5000);
bool hudDirection = false;

// ---------------------------------------------------------------- create

void create() {
    secondCount = 0;
    audioPoints = {};

    // analizador
    analyzer = new AudioAnalyzer(inst);
    length = inst->length;

    float previousNum = 0;
    float num = 0;

    for (int i = 0; i < static_cast<int>(length / milliseconds); i++) {
        std::vector<float> seconds;
        for (int j = 0; j < numberOfBars; j++) {
            num += milliseconds / numberOfBars;
            seconds.push_back(analyzer->analyze(previousNum, num));
            previousNum = num;
        }
        audioPoints.push_back(seconds);
    }

    mySquare = FlxGradient::createGradientFlxSprite(1920, 550, {0xAA000000, 0xFF000000}, 1, 90);
    mySquare->y = 720;
    mySquare->visible = false;
    insert(1, mySquare);

    audioBarsTop = new FlxTypedGroup();
    audioBarsTop->camera = camGame;
    audioBarsTop->visible = false;
    insert(0, audioBarsTop);

    for (int i = 0; i < numberOfBars; i++) {
        int currentColor = (i < numberOfBars / 2) ? barColor1 : barColor2;
        FlxSprite* bar = new FlxSprite().makeGraphic(
            static_cast<int>(FlxG::width / numberOfBars * 0.8),
            static_cast<int>(FlxG::height),
            currentColor
        );
        bar->x = i * (FlxG::width / numberOfBars);
        bar->setGraphicSize(bar->width - 5, bar->height);
        bar->origin.y = 0;
        bar->y = startY;
        bar->updateHitbox();
        audioBarsTop->add(bar);
    }

    // bottom bars
    audioBarsBottom = new FlxTypedGroup();
    audioBarsBottom->camera = camGame;
    audioBarsBottom->visible = false;
    insert(0, audioBarsBottom);

    for (int i = 0; i < numberOfBars; i++) {
        int currentColor = (i < numberOfBars / 2) ? barColor1 : barColor2;
        FlxSprite* bar = new FlxSprite().makeGraphic(
            static_cast<int>(FlxG::width / numberOfBars * 0.8),
            static_cast<int>(FlxG::height),
            currentColor
        );
        bar->x = i * (FlxG::width / numberOfBars);
        bar->setGraphicSize(bar->width - 5, bar->height);
        bar->y = FlxG::height - bar->height;
        bar->updateHitbox();
        audioBarsBottom->add(bar);
    }
}

// ---------------------------------------------------------------- postCreate

void postCreate() {
    blackSquare->makeGraphic(FlxG::width, FlxG::height, 0xFF000000);
    blackSquare->visible = false;
    blackSquare->camera = camHUD;
    insert(0, blackSquare);
}

// ---------------------------------------------------------------- stepHit

void stepHit(int curStep) {
    switch (curStep) {
        case 1280:
            hideStageSprites(false);
            gf->alpha = 0;
            whitesquare->makeGraphic(10000, 10000, 0xFFFFFFFF);
            whitesquare->alpha = 1;
            whitesquare->camera = camGame;
            insert(0, whitesquare);
            for (auto& i : {bf, dad}) {
                if (i != nullptr) {
                    i->shader = new CustomShader("RTXLighting");
                    i->shader->satinColor = {0.5, 0.5, 0.5, 1};
                    i->shader->innerShadowColor = i == bf ? hexatoRGBA(0xFFFFFFFF) : hexatoRGBA(0xFFFFFFFF);
                    i->shader->innerShadowAngle = -90;
                    i->shader->innerShadowDistance = 5;
                    i->shader->layernumbers = 2;
                    i->shader->layerseparation = 7.5;
                }
            }
            break;
        case 1408:
            blackSquareFlash(1, false);
            hideStageSprites(true);
            gf->alpha = 1;
            whitesquare->kill();
            if (bf != nullptr) bf->shader = nullptr;
            if (dad != nullptr) dad->shader = nullptr;
            break;
        case 1424:
            blackSquareFlash(1, false);
            break;
        case 1440:
            blackSquareFlash(1, false);
            break;
        case 1456:
            blackSquareFlash(1, false);
            break;
        case 1472:
            activarParteEpica(0xFFaa00ff, 0xFF00FFFF);
            blackSquareFlash(9, true);
            break;
    }
}

// ---------------------------------------------------------------- beatHit

void beatHit(int curBeat) {
    if (curBeat >= 32 && curBeat < 171) {
        bouncyHud(true);
    } else if (curBeat >= 176 && curBeat < 319) {
        bouncyHud(true);
    } else if (curBeat >= 352 && curBeat < 367 && curBeat % 4 == 0) {
        bouncyHud(true);
    } else if (curBeat >= 368 && curBeat < 395) {
        bouncyHud(true);
    } else if (curBeat >= 400 && curBeat < 559) {
        bouncyHud(true);
    } else {
        bouncyHud(false);
    }
}

void bouncyHud(bool active) {
    if (active) {
        hudDirection = !hudDirection;
        FlxTween::cancelTweensOf(camHUD);
        camHUD->angle = hudDirection ? -3 : 3;
        FlxTween::tween(camHUD, {angle: 0}, 0.25, {
            ease: FlxEase::backOut
        });
    } else {
        FlxTween::cancelTweensOf(camHUD);
        camHUD->angle = 0;
    }
}

// ---------------------------------------------------------------- flash

void blackSquareFlash(float time = 1, bool invert = false) {
    blackSquare->visible = true;
    blackSquare->alpha = invert ? 1 : 0;
    if (invert) {
        FlxTween::tween(blackSquare, {alpha: 0}, time, {ease: FlxEase::lineal});
    } else {
        FlxTween::tween(blackSquare, {alpha: 1}, time, {ease: FlxEase::lineal});
    }
}

void hideStageSprites(bool show) {
    for (auto& sprite : stage->stageSprites) {
        sprite->visible = show;
    }
}

// ---------------------------------------------------------------- update

void update(float elapsed) {
    if (!isEpicPartActive) return;

    if (inst->time >= length) {
        secondCount = 0;
    }

    if ((Math.floor(inst->time / Math.pow(10, exponent)) * Math.pow(10, exponent)) % milliseconds == 0
        || (Math.floor(inst->time / Math.pow(10, exponent)) * Math.pow(10, exponent)) == 0) {
        secondCount = static_cast<int>(
            (Math.floor(inst->time / Math.pow(10, exponent)) * Math.pow(10, exponent)) / milliseconds
        );
    }

    if (inst->time <= length && inst != nullptr) {
        for (int i = 0; i < audioBarsTop->length; i++) {
            audioBarsTop->members[i].scale.y = FlxMath::lerp(
                audioBarsTop->members[i].scale.y,
                audioPoints[secondCount][i] * 0.5,
                FlxMath::bound(elapsed * 60, 0, 1)
            );
            audioBarsTop->members[i].updateHitbox();
            audioBarsTop->members[i].y = startY;
        }

        // update bottom bars
        for (int i = 0; i < audioBarsBottom->length; i++) {
            audioBarsBottom->members[i].scale.y = FlxMath::lerp(
                audioBarsBottom->members[i].scale.y,
                audioPoints[secondCount][i],
                FlxMath::bound(elapsed * 60, 0, 1)
            );
            audioBarsBottom->members[i].updateHitbox();
            audioBarsBottom->members[i].y = FlxG::height - audioBarsBottom->members[i].height;
        }
    }
}

// ---------------------------------------------------------------- parte epica

void activarParteEpica(int color1, int color2) {
    isEpicPartActive = true;

    // show waveforms
    if (mySquare != nullptr) mySquare->visible = true;
    if (audioBarsTop != nullptr) audioBarsTop->visible = true;
    if (audioBarsBottom != nullptr) audioBarsBottom->visible = true;

    // hide gf
    if (gf != nullptr) gf->alpha = 0;

    // hide stage sprites
    hideStageSprites(false);

    // update bar colors
    barColor1 = color1;
    barColor2 = color2;

    for (int i = 0; i < audioBarsTop->length; i++) {
        int currentColor = (i < numberOfBars / 2) ? barColor1 : barColor2;

        FlxSprite* topBar = audioBarsTop->members[i];
        topBar->makeGraphic(static_cast<int>(FlxG::width / numberOfBars * 0.8), static_cast<int>(FlxG::height), currentColor);
        topBar->updateHitbox();

        FlxSprite* bottomBar = audioBarsBottom->members[i];
        bottomBar->makeGraphic(static_cast<int>(FlxG::width / numberOfBars * 0.8), static_cast<int>(FlxG::height), currentColor);
        bottomBar->updateHitbox();
    }

    // apply shader
    for (auto& i : {bf, dad}) {
        if (i != nullptr) {
            i->shader = new CustomShader("RTXLighting");
            i->shader->satinColor = {0, 0, 0, 1};
            i->shader->innerShadowColor = i == bf ? hexatoRGBA(color2) : hexatoRGBA(color1);
            i->shader->innerShadowAngle = -90;
            i->shader->innerShadowDistance = 5;
            i->shader->layernumbers = 2;
            i->shader->layerseparation = 7.5;
        }
    }
}

std::vector<float> hexatoRGBA(int hex) {
    float r = ((hex >> 16) & 0xFF) / 255;
    float g = ((hex >> 8) & 0xFF) / 255;
    float b = (hex & 0xFF) / 255;
    return {r, g, b, 2};
}

void desactivarParteEpica() {
    isEpicPartActive = false;

    if (mySquare != nullptr) mySquare->visible = false;
    if (audioBarsTop != nullptr) audioBarsTop->visible = false;
    if (audioBarsBottom != nullptr) audioBarsBottom->visible = false;

    // show gf
    if (gf != nullptr) gf->alpha = 1;

    // show stage sprites
    hideStageSprites(true);

    // remove shaders
    if (bf != nullptr) bf->shader = nullptr;
    if (dad != nullptr) dad->shader = nullptr;
}
