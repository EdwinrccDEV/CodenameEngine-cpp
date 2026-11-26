// ============================================================================
// Port de assets/songs/winter horrorland/scripts/funniBump.hx
// ============================================================================

void beatHit(int curBeat) {
    switch (curBeat) {
        case 120:
            camZoomingInterval = 2;
            break;
        case 153:
            camZoomingInterval = 4;
            break;
        case 216:
            camZoomingInterval = 2;
            break;
        case 230:
            camZoomingInterval = 4;
            break;
    }
}
