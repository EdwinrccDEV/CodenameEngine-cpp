// ============================================================================
// Port de assets/songs/tutorial/scripts/zoom.hx
//
// Hace zoom al cambiar de camara, cancelando el zoom automatico de los golpes.
// ============================================================================

int lastFocused = -1;
FlxTween* zoomin = nullptr;

void onNoteHit(Dynamic event) {
    event->enableCamZooming = false;
}

void onCameraMove(Dynamic _) {
    if (zoomin != nullptr || lastFocused == curCameraTarget) return;

    lastFocused = curCameraTarget;
    zoomin = FlxTween::tween(FlxG::camera, {zoom: curCameraTarget == 0 ? 1.3 : 1}, Conductor::stepCrochet * 4 / 1000, {
        ease: FlxEase::elasticInOut,
        onComplete: [](Dynamic _) {
            zoomin = nullptr;
        }
    });
}
