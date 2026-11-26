void update(float elapsed) {
    if (FlxG::keys->justPressed->THREE) {
        trace("[state-test] from update() in scripts/state-test.cpp");
        FlxG::switchState(new ModState("MiTest"));
    }
}