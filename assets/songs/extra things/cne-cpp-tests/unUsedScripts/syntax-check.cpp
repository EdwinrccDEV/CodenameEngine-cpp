// ============================================================================
// Prueba de sintaxis del transpilador (no toca nada del juego).
//
// Cubre lo que se agrego despues de portar los scripts de assets/songs/:
// std::floor / std::pow / std::abs / std::to_string y los structured bindings.
// ============================================================================

void postCreate() {
    std::vector<int> values = {10, 20, 30};
    for (auto& [index, value] : values) {
        trace("[syntax] " + std::to_string(index) + " => " + std::to_string(value));
    }

    float f = std::floor(1.9f) + std::pow(2.0f, 3) + std::abs(-4);
    trace("[syntax] floor(1.9) + pow(2, 3) + abs(-4) = " + std::to_string(f));
}
