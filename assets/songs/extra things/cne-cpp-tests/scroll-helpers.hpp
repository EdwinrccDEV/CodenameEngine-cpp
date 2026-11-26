// Compartido por los scripts .cpp de compotandere.
// Los archivos .hpp NO se cargan como script: solo se incluyen con #include.

// Velocidad de giro de la cámara al cantar.
float scrollLerpSpeed(FlxCamera* cam, float offset) {
    return cam->followLerp * offset / 30;
}
