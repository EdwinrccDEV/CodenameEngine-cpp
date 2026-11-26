// ============================================================================
// Port de assets/songs/fresh/scripts/gf-speed.hx
// ============================================================================

void beatHit(int curBeat) {
    switch (curBeat) {
        case 16:
            gfSpeed = 2;
            break;
        case 48:
            gfSpeed = 1;
            break;
        case 80:
            gfSpeed = 2;
            break;
        case 112:
            gfSpeed = 1;
            break;
    }
}
