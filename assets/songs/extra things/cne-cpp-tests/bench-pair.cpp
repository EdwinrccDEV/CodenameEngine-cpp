// Mismo script que bench-pair.hx, pero en C++. Si cambias uno, cambia el otro.
#include "flixel/FlxG.hpp"

std::string benchBuild(int n) {
    std::vector<std::string> parts;
    for (int i = 0; i < n; i++) {
        if (i % 15 == 0) parts.push_back("fizzbuzz");
        else if (i % 3 == 0) parts.push_back("fizz");
        else if (i % 5 == 0) parts.push_back("buzz");
        else parts.push_back(std::to_string(i));
    }
    return parts.join(",");
}

float benchWave(int n) {
    float total = 0;
    for (int i = 0; i < n; i++) {
        total += std::sqrt(i) * 0.5 + std::sin(i * 0.01) + std::cos(i * 0.02) * 0.25;
        if (i % 7 == 0) total -= std::abs(i - 10) * 0.001;
    }
    return total;
}

std::string benchResult() {
    float wave = benchWave(3000);
    return benchBuild(24) + " | " + std::to_string(std::floor(wave * 100) / 100);
}

void postCreate() {
    trace("[bench][cpp] " + benchResult());
}
