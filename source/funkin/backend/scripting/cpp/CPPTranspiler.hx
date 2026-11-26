package funkin.backend.scripting.cpp;


/**
 * Transpilador C++ -> HScript del motor.
 *
 * Recibe C++ y devuelve HScript, sin sistema de archivos: los #include
 * locales los resuelve quien llama, y el resultado se puede cachear.
 * Compilado junto al juego no necesita NDLL ni addon.
 */
class CPPTranspiler {
    /** Tiempo (ms) de la ultima compilacion. */
    public static var lastMs:Float = 0;

    /** Si no es null, `compile` guarda aqui los tiempos por fase (debug). */
    public static var profileData:Array<Dynamic> = null;

    static function mark(name:String, t0:Float) {
        if (profileData != null) profileData.push([name, (haxe.Timer.stamp() - t0) * 1000]);
    }

    public static function compile(source:String, resolver:String->String):String {
        var includes:Array<String> = [];
        var macros:Array<Dynamic> = [];
        var prelude = new StringBuf();
        var visited:Array<String> = [];
        var start = haxe.Timer.stamp();
        var t0 = start;
        var prepared = prepare(source, includes, macros, resolver, prelude, visited);
        mark("prepare", t0);

        t0 = haxe.Timer.stamp();
        var raw = tokenize(prepared);
        mark("tokenize", t0);

        t0 = haxe.Timer.stamp();
        var lam = lambdas(raw, macros, includes);
        mark("lambdas", t0);

        t0 = haxe.Timer.stamp();
        var ini = initializers(lam);
        mark("initializers", t0);

        t0 = haxe.Timer.stamp();
        var toks = switches(ini);
        mark("switches", t0);

        t0 = haxe.Timer.stamp();
        var out = rewrite(toks, macros, includes);
        mark("rewrite", t0);

        t0 = haxe.Timer.stamp();
        var body = emit(out);
        mark("emit", t0);
        lastMs = Math.round((haxe.Timer.stamp() - start) * 10000) / 10;

        var head = "";
        var i = 0;
        while (i < includes.length) {
            // LF fijo: el resultado solo lo lee el parser del motor, asi que no
            // depende de los saltos de linea del archivo fuente.
            head += "import " + includes[i] + ";\n";
            i++;
        }
        return head + prelude.toString() + body;
    }

    // =====================================================================
    // PREPROCESSOR + COMMENTS
    // =====================================================================

    public static function prepare(source:String, includes:Array<String>, macros:Array<Dynamic>,
        resolver:String->String = null, prelude:StringBuf = null, visited:Array<String> = null):String {
        var src = source.split("\r\n").join("\n").split("\r").join("\n");
        var lines = src.split("\n");
        var outLines:Array<String> = [];
        var i = 0;
        while (i < lines.length) {
            var line = lines[i];
            var t = StringTools.trim(line);
            if (t.length > 0 && t.charAt(0) == "#") {
                var rest = StringTools.trim(t.substr(1));
                // join line continuations
                while (rest.length > 0 && rest.charAt(rest.length - 1) == "\\" && i + 1 < lines.length) {
                    rest = StringTools.trim(rest.substr(0, rest.length - 1)) + " " + StringTools.trim(lines[i + 1]);
                    i++;
                }
                handleDirective(rest, includes, macros, resolver, prelude, visited);
                outLines.push("");
            } else {
                outLines.push(line);
            }
            i++;
        }
        var joined = outLines.join("\n");
        if (joined.indexOf("//") < 0 && joined.indexOf("/*") < 0) return joined;
        return stripComments(joined);
    }

    /** Transpiles a file pulled in by `#include "algo.hpp"`. */
    static function compileFragment(src:String, includes:Array<String>, macros:Array<Dynamic>,
        resolver:String->String, visited:Array<String>, prelude:StringBuf):String {
        // Solo se cachea un .hpp sin directivas: asi no se pierden imports ni macros.
        var cacheable = src.indexOf("#include") < 0 && src.indexOf("#define") < 0 && src.indexOf("#undef") < 0;
        var key:String = null;
        if (cacheable) {
            var sig = new StringBuf();
            sig.add(CPPTranspilerCache.VERSION);
            sig.add("|");
            var k = 0;
            while (k < macros.length) {
                sig.add(macros[k][0]);
                sig.add("=");
                sig.add(Std.string(macros[k][1]));
                sig.add(";");
                k++;
            }
            sig.add(src);
            key = CPPTranspilerCache.hash(sig.toString());
            var cached = CPPTranspilerCache.getFragment(key);
            if (cached != null) return cached;
        }
        var prepared = prepare(src, includes, macros, resolver, prelude, visited);
        var out = emit(rewrite(switches(initializers(lambdas(tokenize(prepared), macros, includes))), macros, includes));
        if (key != null) CPPTranspilerCache.setFragment(key, out);
        return out;
    }

    static function handleDirective(rest:String, includes:Array<String>, macros:Array<Dynamic>,
        resolver:String->String = null, prelude:StringBuf = null, visited:Array<String> = null) {
        var word = firstWord(rest);
        if (word == "include") {
            var p = includePath(rest);
            if (p != null) {
                var isEngineImport = addInclude(p, includes);
                // #include "utils.hpp" -> inline the file (multi file scripts)
                if (!isEngineImport && resolver != null && prelude != null && visited != null
                    && visited.indexOf(p) < 0) {
                    visited.push(p);
                    var txt:String = null;
                    try txt = resolver(p) catch (e:Dynamic) txt = null;
                    if (txt != null) {
                        prelude.add(compileFragment(txt, includes, macros, resolver, visited, prelude));
                        prelude.add("
");
                    }
                }
            }
        } else if (word == "define") {
            var body = StringTools.trim(rest.substr(word.length));
            var name = firstWord(body);
            if (name.length > 0) {
                var value = StringTools.trim(body.substr(name.length));
                if (value.length > 0 && value.charAt(0) != "(") setMacro(macros, name, value);
            }
        } else if (word == "undef") {
            var name = firstWord(StringTools.trim(rest.substr(word.length)));
            removeMacro(macros, name);
        }
        // #pragma, #if, #ifdef, #endif, ... are ignored on purpose
    }

    public static function includePath(rest:String):String {
        var q = rest.indexOf("\"");
        if (q >= 0) {
            var q2 = rest.indexOf("\"", q + 1);
            if (q2 > q) return rest.substring(q + 1, q2);
        }
        var a = rest.indexOf("<");
        var b = rest.indexOf(">");
        if (a >= 0 && b > a) return rest.substring(a + 1, b);
        return null;
    }

    public static function addInclude(rawPath:String, includes:Array<String>):Bool {
        var p = StringTools.trim(rawPath).split("\\").join("/");
        var slash = p.lastIndexOf("/");
        var dot = p.lastIndexOf(".");
        if (dot > slash) p = p.substr(0, dot);
        var dotted = p.split("/").join(".");
        var low = dotted.toLowerCase();
        var known = low.indexOf("funkin.") == 0 || low.indexOf("flixel.") == 0 || low.indexOf("lime.") == 0
            || low.indexOf("openfl.") == 0 || low.indexOf("animate.") == 0 || low.indexOf("hscript.") == 0
            || low.indexOf("haxe.") == 0 || low.indexOf("sys.") == 0;
        if (!known) return false;
        if (includes.indexOf(dotted) < 0) includes.push(dotted);
        return true;
    }

    static function setMacro(macros:Array<Dynamic>, name:String, value:String) {
        var i = 0;
        while (i < macros.length) {
            if (macros[i][0] == name) {
                macros[i][1] = value;
                return;
            }
            i++;
        }
        macros.push([name, value]);
    }

    static function removeMacro(macros:Array<Dynamic>, name:String) {
        var i = 0;
        while (i < macros.length) {
            if (macros[i][0] == name) macros[i][1] = null;
            i++;
        }
    }

    static function macroValue(macros:Array<Dynamic>, name:String):String {
        var i = 0;
        while (i < macros.length) {
            if (macros[i][0] == name && macros[i][1] != null) return macros[i][1];
            i++;
        }
        return null;
    }

    public static function stripComments(src:String):String {
        var buf = new StringBuf();
        var i = 0;
        var n = src.length;
        while (i < n) {
            var c = src.charAt(i);
            if (c == "/" && i + 1 < n && src.charAt(i + 1) == "/") {
                while (i < n && src.charAt(i) != "\n") i++;
                continue;
            }
            if (c == "/" && i + 1 < n && src.charAt(i + 1) == "*") {
                i += 2;
                while (i < n) {
                    if (src.charAt(i) == "*" && i + 1 < n && src.charAt(i + 1) == "/") {
                        i += 2;
                        break;
                    }
                    if (src.charAt(i) == "\n") buf.add("\n");
                    i++;
                }
                continue;
            }
            if (c == "\"" || c == "'") {
                var quote = c;
                buf.add(c);
                i++;
                while (i < n) {
                    var ch = src.charAt(i);
                    buf.add(ch);
                    i++;
                    if (ch == "\\") {
                        if (i < n) {
                            buf.add(src.charAt(i));
                            i++;
                        }
                        continue;
                    }
                    if (ch == quote) break;
                }
                continue;
            }
            buf.add(c);
            i++;
        }
        return buf.toString();
    }

    // =====================================================================
    // TOKENIZER
    // =====================================================================
    // Token = [kind, text, line]
    // kind is one of: "id", "num", "str", "op"

    public static function tokenize(src:String):Array<Dynamic> {
        var toks:Array<Dynamic> = [];
        var i = 0;
        var n = src.length;
        var line = 1;
        while (i < n) {
            var c = src.charAt(i);
            if (c == "\n") {
                line++;
                i++;
                continue;
            }
            if (c == " " || c == "\t" || c == "\r") {
                i++;
                continue;
            }
            if (c == "\"") {
                var st = i;
                i++;
                while (i < n) {
                    var ch = src.charAt(i);
                    if (ch == "\\") {
                        i += 2;
                        continue;
                    }
                    i++;
                    if (ch == "\"") break;
                }
                toks.push(["str", src.substring(st, i), line]);
                continue;
            }
            if (c == "'") {
                var inner = "";
                i++;
                while (i < n) {
                    var ch = src.charAt(i);
                    if (ch == "\\") {
                        inner += ch;
                        i++;
                        if (i < n) {
                            inner += src.charAt(i);
                            i++;
                        }
                        continue;
                    }
                    if (ch == "'") {
                        i++;
                        break;
                    }
                    inner += ch;
                    i++;
                }
                toks.push(["str", "\"" + escapeString(inner) + "\"", line]);
                continue;
            }
            if (isDigit(c) || (c == "." && isDigit(src.charAt(i + 1)))) {
                var st = i;
                var seenDot = (c == ".");
                i++;
                var isHex = false;
                while (i < n) {
                    var ch = src.charAt(i);
                    if (isDigit(ch)) {
                        i++;
                        continue;
                    }
                    if ((ch == "x" || ch == "X") && i == st + 1) {
                        isHex = true;
                        i++;
                        continue;
                    }
                    if (isHex && isHexDigit(ch)) {
                        i++;
                        continue;
                    }
                    if (ch == "." && !seenDot) {
                        seenDot = true;
                        i++;
                        continue;
                    }
                    if (ch == "e" || ch == "E") {
                        i++;
                        if (i < n && (src.charAt(i) == "+" || src.charAt(i) == "-")) i++;
                        continue;
                    }
                    if (ch == "f" || ch == "F" || ch == "u" || ch == "U" || ch == "l" || ch == "L") {
                        i++;
                        continue;
                    }
                    break;
                }
                toks.push(["num", cleanNumber(src.substring(st, i)), line]);
                continue;
            }
            if (isIdentStart(c)) {
                var st = i;
                i++;
                while (i < n && isIdentChar(src.charAt(i))) i++;
                toks.push(["id", src.substring(st, i), line]);
                continue;
            }
            var three = i + 3 <= n ? src.substring(i, i + 3) : "";
            var two = i + 2 <= n ? src.substring(i, i + 2) : "";
            if (three == "??=" || three == "<<=" || three == ">>=") {
                toks.push(["op", three, line]);
                i += 3;
                continue;
            }
            if (two == "::") {
                toks.push(["op", ".", line]);
                i += 2;
                continue;
            }
            if (two == "->") {
                toks.push(["op", arrowIsLambda(toks, src, i + 2) ? "->" : ".", line]);
                i += 2;
                continue;
            }
            if (two == "??" || two == "?." || two == "++" || two == "--" || two == "+=" || two == "-="
                || two == "*=" || two == "/=" || two == "%=" || two == "==" || two == "!=" || two == "<="
                || two == ">=" || two == "&&" || two == "||" || two == "<<" || two == ">>" || two == "=>") {
                toks.push(["op", two, line]);
                i += 2;
                continue;
            }
            toks.push(["op", c, line]);
            i++;
        }
        return toks;
    }

    // =====================================================================
    // LAMBDAS + ARROW DISAMBIGUATION
    // =====================================================================

    /** True when `->` starts a lambda ( `() -> {` ) instead of member access. */
    static function arrowIsLambda(toks:Array<Dynamic>, src:String, after:Int):Bool {
        var j = after;
        while (j < src.length) {
            var c = src.charAt(j);
            if (c == " " || c == "	" || c == "
" || c == "
") j++;
            else break;
        }
        if (j < src.length && src.charAt(j) == "{") return true;
        if (toks.length == 0) return true;
        var last = toks[toks.length - 1];
        if (last[1] != ")") return false;
        var open = matchingOpen(toks, toks.length - 1);
        if (open <= 0) return true;
        var before = toks[open - 1];
        if (before[0] == "id") {
            // foo(...) -> x is a call, so `->` is member access;
            // `function(...) -> x` is a lambda with a return type.
            return before[1] == "function" || before[1] == "return";
        }
        if (before[0] == "str" || before[0] == "num") return false;
        return true;
    }

    static function matchingOpen(toks:Array<Dynamic>, closeIdx:Int):Int {
        var depth = 0;
        var k = closeIdx;
        while (k >= 0) {
            var s:String = toks[k][1];
            if (s == ")") depth++;
            else if (s == "(") {
                depth--;
                if (depth == 0) return k;
            }
            k--;
        }
        return -1;
    }

    /** Index of the token closing the group opened at `start`, or -1. */
    static function matchingClose(toks:Array<Dynamic>, start:Int, open:String, close:String):Int {
        var depth = 0;
        var k = start;
        while (k < toks.length) {
            var s:String = toks[k][1];
            if (s == open) depth++;
            else if (s == close) {
                depth--;
                if (depth == 0) return k;
            }
            k++;
        }
        return -1;
    }

    /**
     * Rewrites C++ lambdas into HScript anonymous functions:
     *   [](float a, float b) { ... }   -> function(a, b) { ... }
     *   [&](int x) -> void { ... }     -> function(x) { ... }
     * Capture lists are dropped: HScript closures already capture by reference.
     */
    public static function lambdas(toks:Array<Dynamic>, macros:Array<Dynamic>, includes:Array<String>):Array<Dynamic> {
        var out:Array<Dynamic> = [];
        var changed = false;
        var i = 0;
        while (i < toks.length) {
            var t = toks[i];
            if (t[0] == "op" && t[1] == "[" && lambdaStart(toks, i) && isCaptureList(toks, i)) {
                var j = matchingClose(toks, i, "[", "]");
                if (j > 0 && j + 1 < toks.length && toks[j + 1][1] == "(") {
                    var m = matchingClose(toks, j + 1, "(", ")");
                    if (m > 0) {
                        out.push(tok("id", "function", ln(t)));
                        out.push(tok("op", "(", ln(t)));
                        var ps = convertParams(toks, j + 2, m, macros, includes);
                        for (q in ps) out.push([q[0], q[1], ln(t)]);
                        out.push(tok("op", ")", ln(t)));
                        changed = true;
                        i = m + 1;
                        continue;
                    }
                }
            }
            out.push(t);
            i++;
        }
        if (!changed) return toks;
        return dropLambdaReturnTypes(out);
    }

    /** `function(a) -> int { }` (C++ trailing return type) -> `function(a) { }` */
    static function dropLambdaReturnTypes(toks:Array<Dynamic>):Array<Dynamic> {
        var res:Array<Dynamic> = [];
        var i = 0;
        while (i < toks.length) {
            if (i + 2 < toks.length && toks[i][0] == "op" && toks[i][1] == "->"
                && kindOf(toks[i + 1]) == "id" && toks[i + 2][1] == "{"
                && res.length > 0 && res[res.length - 1][1] == ")") {
                i += 2;
                continue;
            }
            res.push(toks[i]);
            i++;
        }
        return res;
    }

    /** A capture list can only appear where an expression starts. */
    static function lambdaStart(toks:Array<Dynamic>, i:Int):Bool {
        if (i == 0) return true;
        var before = toks[i - 1];
        var s:String = before[1];
        if (before[0] == "id") return s == "return" || s == "function";
        if (before[0] == "str" || before[0] == "num") return false;
        return s != ")" && s != "]" && s != ".";
    }

    // =====================================================================
    // SWITCH / CASE
    // =====================================================================

    /**
     * C++ switches use `break;` and fall through between labels; HScript has
     * neither. This drops the `break;` of every case (keeping the ones that
     * belong to a loop) and merges consecutive labels:
     *   case 1: case 2: body   ->   case 1, 2: body
     */
    public static function switches(toks:Array<Dynamic>):Array<Dynamic> {
        var hasSwitch = false;
        for (t in toks) {
            if (text(t) == "switch") {
                hasSwitch = true;
                break;
            }
        }
        if (!hasSwitch) return toks;

        var drop:Array<Bool> = [];
        for (t in toks) drop.push(false);
        var changed = false;

        var i = 0;
        while (i < toks.length) {
            if (text(toks[i]) == "switch" && i + 1 < toks.length && text(toks[i + 1]) == "(") {
                var close = matchingClose(toks, i + 1, "(", ")");
                if (close > 0 && close + 1 < toks.length && text(toks[close + 1]) == "{") {
                    var end = matchingClose(toks, close + 1, "{", "}");
                    if (end > 0) changed = markSwitchBreaks(toks, close + 2, end, drop) || changed;
                }
            }
            i++;
        }

        var out:Array<Dynamic> = [];
        i = 0;
        while (i < toks.length) {
            if (drop[i]) {
                i++;
                continue;
            }
            if (text(toks[i]) == "case") {
                var labels:Array<Array<Dynamic>> = [];
                var j = i;
                while (j < toks.length && text(toks[j]) == "case") {
                    var col = caseColon(toks, j + 1);
                    if (col < 0) break;
                    labels.push(sliceTokens(toks, j + 1, col));
                    j = col + 1;
                    if (j >= toks.length || text(toks[j]) != "case") break;
                }
                if (labels.length > 0) {
                    out.push(tok("id", "case", ln(toks[i])));
                    var caseLn = ln(toks[i]);
                    var k = 0;
                    while (k < labels.length) {
                        if (k > 0) out.push(tok("op", ",", caseLn));
                        for (q in labels[k]) out.push([q[0], q[1], caseLn]);
                        k++;
                    }
                    out.push(tok("op", ":", ln(toks[i])));
                    if (labels.length > 1) changed = true;
                    i = j;
                    continue;
                }
            }
            out.push(toks[i]);
            i++;
        }
        return changed ? out : toks;
    }

    /** Marks the `break;` of every case that is not inside a loop. */
    static function markSwitchBreaks(toks:Array<Dynamic>, from:Int, to:Int, drop:Array<Bool>):Bool {
        var changed = false;
        var stack:Array<Bool> = [];
        var pendingLoop = false;
        var pdepth = 0;
        var i = from;
        while (i < to) {
            var s = text(toks[i]);
            if (kindOf(toks[i]) == "id" && (s == "for" || s == "while" || s == "do")) {
                pendingLoop = true;
                i++;
                continue;
            }
            if (s == "{") {
                stack.push(pendingLoop);
                pendingLoop = false;
                i++;
                continue;
            }
            if (s == "}") {
                if (stack.length > 0) stack.pop();
                pendingLoop = false;
                i++;
                continue;
            }
            if (s == "(" || s == "[") pdepth++;
            else if (s == ")" || s == "]") pdepth--;
            if (s == ";" && pdepth <= 0) pendingLoop = false;
            if (s == "break" && !inLoop(stack)) {
                drop[i] = true;
                if (i + 1 < to && text(toks[i + 1]) == ";") drop[i + 1] = true;
                changed = true;
            }
            i++;
        }
        return changed;
    }

    /** True when the `:` is closing a `case` / `default` label. */
    static function isCaseLabel(out:Array<Dynamic>):Bool {
        var k = out.length - 1;
        while (k >= 0) {
            var t = out[k];
            var s:String = t[1];
            if (t[0] == "id" && (s == "case" || s == "default")) return true;
            if (s == ";" || s == "{" || s == "}" || s == "?" || s == "(" || s == ")" || s == "[" || s == "]") return false;
            k--;
        }
        return false;
    }

    static function inLoop(stack:Array<Bool>):Bool {
        for (b in stack) if (b) return true;
        return false;
    }

    /** Index of the `:` that closes a case label, or -1. */
    static function caseColon(toks:Array<Dynamic>, start:Int):Int {
        var d = 0;
        var ternaries = 0;
        var i = start;
        while (i < toks.length) {
            var s = text(toks[i]);
            if (s == "(" || s == "[" || s == "{") d++;
            else if (s == ")" || s == "]" || s == "}") {
                d--;
                if (d < 0) return -1;
            }
            else if (s == "?") ternaries++;
            else if (s == ":") {
                if (d == 0 && ternaries == 0) return i;
                if (ternaries > 0) ternaries--;
            }
            else if (s == "case" || s == "default") return -1;
            i++;
        }
        return -1;
    }

    // =====================================================================
    // INITIALIZER LISTS  ( {a, b} -> [a, b] )
    // =====================================================================

    /**
     * C++ brace initialization is an array in HScript:
     *   {alpha: 0}      stays an object literal (it has `:`)
     *   {0.5, 0.5, 1}   becomes [0.5, 0.5, 1]
     */
    public static function initializers(toks:Array<Dynamic>):Array<Dynamic> {
        var out:Array<Dynamic> = [];
        var changed = false;
        var i = 0;
        while (i < toks.length) {
            var t = toks[i];
            if (text(t) == "{" && startsInitializer(out)) {
                var j = matchingClose(toks, i, "{", "}");
                if (j > 0 && isInitializerBody(toks, i + 1, j)) {
                    out.push(tok("op", "[", ln(t)));
                    pushAll(out, initializers(sliceTokens(toks, i + 1, j)));
                    out.push(tok("op", "]", ln(toks[j])));
                    changed = true;
                    i = j + 1;
                    continue;
                }
            }
            out.push(t);
            i++;
        }
        return changed ? out : toks;
    }

    /** True when the `{` can only be an expression (not a block). */
    static function startsInitializer(out:Array<Dynamic>):Bool {
        if (out.length == 0) return true;
        var t = out[out.length - 1];
        var s:String = t[1];
        if (t[0] == "id") return s == "return";
        if (t[0] == "str" || t[0] == "num") return false;
        return s == "=" || s == "," || s == "(" || s == "[" || s == ":" || s == "?"
            || s == "&&" || s == "||" || s == "+" || s == "-" || s == "*" || s == "/"
            || s == "=>" || s == "->" || s == "==" || s == "!=";
    }

    /** An object literal has `:` at top level, a block has `;`. */
    static function isInitializerBody(toks:Array<Dynamic>, from:Int, to:Int):Bool {
        var d = 0;
        var i = from;
        while (i < to) {
            var s = text(toks[i]);
            if (s == "(" || s == "[" || s == "{") d++;
            else if (s == ")" || s == "]" || s == "}") d--;
            else if ((s == ":" || s == ";") && d == 0) return false;
            else if (d == 0 && kindOf(toks[i]) == "id" && (s == "case" || s == "default" || s == "for" || s == "if")) return false;
            i++;
        }
        return true;
    }

    /** True when the `{` just pushed opens an object literal instead of a block. */
    static function isObjectBrace(out:Array<Dynamic>):Bool {
        if (out.length < 2) return false;
        var prev:String = out[out.length - 2][1];
        return prev == "=" || prev == "," || prev == "(" || prev == ":" || prev == "["
            || prev == "return" || prev == "?" || prev == "&&" || prev == "||"
            || prev == "=>" || prev == "->" || prev == "+";
    }

    /** True when `[` opens a capture list (`[]`, `[&]`, `[=]`, `[this]`, `[&a, b]`). */
    static function isCaptureList(toks:Array<Dynamic>, i:Int):Bool {
        var j = matchingClose(toks, i, "[", "]");
        if (j < 0) return false;
        if (j + 1 >= toks.length || toks[j + 1][1] != "(") return false;
        var k = i + 1;
        while (k < j) {
            var tk = toks[k];
            var s:String = tk[1];
            if (tk[0] == "op") {
                if (s != "&" && s != "=" && s != "," && s != "*") return false;
            } else if (tk[0] != "id") return false;
            k++;
        }
        return true;
    }

    static function cleanNumber(raw:String):String {
        var r = raw;
        var hex = r.length > 1 && r.charAt(0) == "0" && (r.charAt(1) == "x" || r.charAt(1) == "X");
        while (r.length > 0) {
            var last = r.charAt(r.length - 1);
            var suffix = hex
                ? (last == "u" || last == "U" || last == "l" || last == "L")
                : (last == "f" || last == "F" || last == "u" || last == "U" || last == "l" || last == "L");
            if (!suffix) break;
            r = r.substr(0, r.length - 1);
        }
        return r;
    }

    static function escapeString(inner:String):String {
        var res = new StringBuf();
        var i = 0;
        while (i < inner.length) {
            var c = inner.charAt(i);
            if (c == "\\") {
                res.add(c);
                i++;
                if (i < inner.length) {
                    res.add(inner.charAt(i));
                    i++;
                }
                continue;
            }
            if (c == "\"") {
                res.add("\\\"");
                i++;
                continue;
            }
            res.add(c);
            i++;
        }
        return res.toString();
    }

    static function isDigit(c:String):Bool {
        if (c.length == 0) return false;
        var code = c.charCodeAt(0);
        return code >= 48 && code <= 57;
    }

    static function isHexDigit(c:String):Bool {
        if (c.length == 0) return false;
        var code = c.charCodeAt(0);
        return (code >= 48 && code <= 57) || (code >= 65 && code <= 70) || (code >= 97 && code <= 102);
    }

    static function isIdentStart(c:String):Bool {
        if (c.length == 0) return false;
        var code = c.charCodeAt(0);
        return (code >= 65 && code <= 90) || (code >= 97 && code <= 122) || code == 95;
    }

    static function isIdentChar(c:String):Bool {
        return isIdentStart(c) || isDigit(c);
    }

    static function firstWord(s:String):String {
        var i = 0;
        while (i < s.length && !isIdentStart(s.charAt(i))) i++;
        var st = i;
        while (i < s.length && isIdentChar(s.charAt(i))) i++;
        return s.substring(st, i);
    }

    // =====================================================================
    // TOKEN HELPERS
    // =====================================================================

    static function kindOf(t:Dynamic):String {
        return t[0];
    }

    static function text(t:Dynamic):String {
        return t[1];
    }

    static function ln(t:Dynamic):Int {
        return t[2];
    }

    static function tok(kind:String, txt:String, ln:Int):Array<Dynamic> {
        return [kind, txt, ln];
    }

    static function qualifierList():Array<String> {
        return ["static", "inline", "virtual", "override", "extern", "constexpr", "const", "mutable",
            "explicit", "final", "noexcept", "register", "thread_local", "volatile", "typename"];
    }

    static function keywordList():Array<String> {
        return ["if", "else", "for", "while", "do", "switch", "case", "default", "return", "break",
            "continue", "try", "catch", "throw", "new", "delete", "var", "function", "import", "using",
            "this", "super", "null", "true", "false", "and", "or", "not", "template", "enum"];
    }

    static function matchParen(tokens:Array<Dynamic>, openIdx:Int):Int {
        var depth = 0;
        var i = openIdx;
        while (i < tokens.length) {
            var c = text(tokens[i]);
            if (c == "(" || c == "[" || c == "{") depth++;
            else if (c == ")" || c == "]" || c == "}") {
                depth--;
                if (depth == 0) return i;
            }
            i++;
        }
        return -1;
    }

    static function topLevelIndex(list:Array<Dynamic>, ch:String):Int {
        var depth = 0;
        var i = 0;
        while (i < list.length) {
            var c = text(list[i]);
            if (c == "(" || c == "[" || c == "{") depth++;
            else if (c == ")" || c == "]" || c == "}") depth--;
            else if (c == ch && depth == 0) return i;
            i++;
        }
        return -1;
    }

    static function splitTopLevel(list:Array<Dynamic>, ch:String):Array<Dynamic> {
        var parts:Array<Dynamic> = [];
        var cur:Array<Dynamic> = [];
        var depth = 0;
        var i = 0;
        while (i < list.length) {
            var c = text(list[i]);
            if (c == "(" || c == "[" || c == "{") depth++;
            else if (c == ")" || c == "]" || c == "}") depth--;
            if (c == ch && depth == 0) {
                parts.push(cur);
                cur = [];
                i++;
                continue;
            }
            cur.push(list[i]);
            i++;
        }
        parts.push(cur);
        return parts;
    }

    /**
     * `for (auto& [key, value] : map)` -> ["key", "value"].
     * Devuelve null si el for no usa structured bindings.
     */
    static function structuredBindingNames(list:Array<Dynamic>, colon:Int):Array<String> {
        var depth = 0;
        var open = -1;
        var i = 0;
        while (i < colon) {
            var c = text(list[i]);
            if (c == "[") {
                if (depth == 0 && open < 0) open = i;
                depth++;
            } else if (c == "]") {
                depth--;
                if (depth == 0 && open >= 0) {
                    var names:Array<String> = [];
                    var parts = splitTopLevel(sliceTokens(list, open + 1, i), ",");
                    var k = 0;
                    while (k < parts.length) {
                        var id = lastId(parts[k], 0, parts[k].length);
                        if (id != null) names.push(id);
                        k++;
                    }
                    return names.length == 2 ? names : null;
                }
            } else if (c == "(" || c == "{") depth++;
            else if (c == ")" || c == "}") depth--;
            i++;
        }
        return null;
    }

    /** std::floor, std::pow, ... -> la funcion equivalente de Math. */
    static function stdMathName(name:String):String {
        switch (name) {
            case "floor": return "Math.floor";
            case "ceil": return "Math.ceil";
            case "round": return "Math.round";
            case "abs" | "fabs": return "Math.abs";
            case "pow": return "Math.pow";
            case "exp": return "Math.exp";
            case "log": return "Math.log";
            case "sqrt": return "Math.sqrt";
            case "sin": return "Math.sin";
            case "cos": return "Math.cos";
            case "tan": return "Math.tan";
            case "asin": return "Math.asin";
            case "acos": return "Math.acos";
            case "atan": return "Math.atan";
            case "atan2": return "Math.atan2";
            case "min": return "Math.min";
            case "max": return "Math.max";
            default: return null;
        }
    }

    static function lastId(list:Array<Dynamic>, from:Int, to:Int):String {
        var i = to - 1;
        while (i >= from) {
            if (kindOf(list[i]) == "id") return text(list[i]);
            i--;
        }
        return null;
    }

    static function pushAll(out:Array<Dynamic>, list:Array<Dynamic>) {
        var i = 0;
        while (i < list.length) {
            out.push(list[i]);
            i++;
        }
    }

    // =====================================================================
    // REWRITER
    // =====================================================================

    public static function rewrite(tokens:Array<Dynamic>, macros:Array<Dynamic>, includes:Array<String>):Array<Dynamic> {
        var out:Array<Dynamic> = [];
        var keywords = keywordList();
        var i = 0;
        var stmtStart = true;
        var openBraces = 0;
        var skipDepths:Array<Int> = [];

        while (i < tokens.length) {
            var t = tokens[i];
            var tx = text(t);
            var kd = kindOf(t);

            // class / struct / namespace / enum headers are unwrapped
            if (stmtStart && kd == "id" && (tx == "class" || tx == "struct" || tx == "namespace" || tx == "enum")) {
                var j = i + 1;
                while (j < tokens.length && text(tokens[j]) != "{") j++;
                if (j < tokens.length) {
                    openBraces++;
                    skipDepths.push(openBraces);
                    i = j + 1;
                    stmtStart = true;
                    continue;
                }
            }

            // template <...> is dropped, the function after it is kept
            if (stmtStart && tx == "template" && i + 1 < tokens.length && text(tokens[i + 1]) == "<") {
                i = matchParen(tokens, i + 1) + 1;
                if (i <= 0) i = tokens.length;
                stmtStart = true;
                continue;
            }

            // public: / private: / protected:
            if (stmtStart && (tx == "public" || tx == "private" || tx == "protected")
                && i + 1 < tokens.length && text(tokens[i + 1]) == ":") {
                i += 2;
                continue;
            }

            // using namespace std;  /  using Alias = Type;
            if (stmtStart && tx == "using") {
                while (i < tokens.length && text(tokens[i]) != ";") i++;
                if (i < tokens.length) i++;
                continue;
            }

            // typedef ...;
            if (stmtStart && tx == "typedef") {
                while (i < tokens.length && text(tokens[i]) != ";") i++;
                if (i < tokens.length) i++;
                continue;
            }

            // delete player; (nothing to free in HScript)
            if (stmtStart && tx == "delete") {
                while (i < tokens.length && text(tokens[i]) != ";") i++;
                if (i < tokens.length) i++;
                continue;
            }

            // catch (std::exception& e) -> catch (e)
            if (tx == "catch" && i + 1 < tokens.length && text(tokens[i + 1]) == "(") {
                var cclose = matchParen(tokens, i + 1);
                if (cclose > 0) {
                    var cnm = lastId(tokens, i + 2, cclose);
                    if (cnm == null) cnm = "e";
                    out.push(tok("id", "catch", ln(tokens[i])));
                    out.push(tok("op", "(", ln(tokens[i])));
                    out.push(tok("id", cnm, ln(tokens[i])));
                    out.push(tok("op", ":", ln(tokens[i])));
                    out.push(tok("id", "Dynamic", ln(tokens[i])));
                    out.push(tok("op", ")", ln(tokens[i])));
                    i = cclose + 1;
                    stmtStart = false;
                    continue;
                }
            }

            // for (...) -> for (i in ...)
            if (stmtStart && tx == "for" && i + 1 < tokens.length && text(tokens[i + 1]) == "(") {
                var closeIdx = matchParen(tokens, i + 1);
                if (closeIdx > 0) {
                    var conv = convertFor(tokens, i, closeIdx, macros, includes);
                    if (conv != null) {
                        pushAll(out, conv);
                        i = closeIdx + 1;
                        stmtStart = false;
                        continue;
                    }
                }
            }

            // declarations / function definitions
            if (stmtStart && kd == "id" && keywords.indexOf(tx) < 0) {
                var decl:Dynamic = tryDeclaration(tokens, i, macros, includes);
                if (decl != null) {
                    if (decl.drop) {
                        i = decl.end;
                        stmtStart = true;
                        continue;
                    }
                    pushAll(out, decl.tokens);
                    i = decl.end;
                    stmtStart = decl.stmtStart;
                    continue;
                }
            }

            if (tx == "{") {
                openBraces++;
                out.push(t);
                i++;
                // `{` after `=`, `,`, `(`, `:` ... is an object literal, not a block
                stmtStart = !isObjectBrace(out);
                continue;
            }
            if (tx == "}") {
                var sd = skipDepths.length;
                if (sd > 0 && openBraces == skipDepths[sd - 1]) {
                    skipDepths.pop();
                    openBraces--;
                    i++;
                    if (i < tokens.length && text(tokens[i]) == ";") i++; // class Foo { ... };
                    stmtStart = true;
                    continue;
                }
                openBraces--;
                out.push(t);
                i++;
                stmtStart = true;
                continue;
            }
            if (tx == ";") {
                out.push(t);
                i++;
                stmtStart = true;
                continue;
            }

            // console output: std::cout << ... << std::endl;
            if (kd == "id" && isCoutChain(tokens, i)) {
                var semi = i;
                var sdepth = 0;
                while (semi < tokens.length) {
                    var sc = text(tokens[semi]);
                    if (sc == "(" || sc == "[" || sc == "{") sdepth++;
                    else if (sc == ")" || sc == "]" || sc == "}") sdepth--;
                    if (sc == ";" && sdepth <= 0) break;
                    semi++;
                }
                if (semi < tokens.length) {
                    var chain = sliceTokens(tokens, i, semi);
                    var parts = splitTopLevel(chain, "<<");
                    var coutTokens:Array<Dynamic> = [tok("id", "trace", ln(tokens[i])), tok("op", "(", ln(tokens[i]))];
                    var written = 0;
                    var pi = 0;
                    while (pi < parts.length) {
                        var part:Array<Dynamic> = parts[pi];
                        pi++;
                        if (isStreamName(part) || isNewlinePart(part)) continue;
                        if (written > 0) coutTokens.push(tok("op", ",", ln(tokens[i])));
                        pushAll(coutTokens, rewriteExpression(part, macros, includes));
                        written++;
                    }
                    if (written == 0) coutTokens.push(tok("str", "\"\"", ln(tokens[i])));
                    coutTokens.push(tok("op", ")", ln(tokens[i])));
                    coutTokens.push(tok("op", ";", ln(tokens[i])));
                    pushAll(out, coutTokens);
                    i = semi + 1;
                    stmtStart = true;
                    continue;
                }
            }

            // console output: printf("x = %d", x);
            if (kd == "id" && (tx == "printf" || tx == "puts") && i + 1 < tokens.length && text(tokens[i + 1]) == "(") {
                var pfClose = matchParen(tokens, i + 1);
                if (pfClose > 0) {
                    var pfArgs = splitTopLevel(sliceTokens(tokens, i + 2, pfClose), ",");
                    pushAll(out, printfTokens(tx, pfArgs, macros, includes, ln(tokens[i])));
                    i = pfClose + 1;
                    stmtStart = false;
                    continue;
                }
            }

            // std::vector helpers: v.push_back(x) -> v.push(x), v.size() -> v.length
            if ((tx == "push_back" || tx == "pop_back" || tx == "size")
                && out.length > 0 && text(out[out.length - 1]) == "."
                && i + 1 < tokens.length && text(tokens[i + 1]) == "(") {
                var stdClose = matchParen(tokens, i + 1);
                if (stdClose > 0) {
                    if (tx == "size") {
                        out.push(tok("id", "length", ln(tokens[i])));
                        i = stdClose + 1;
                        stmtStart = false;
                        continue;
                    }
                    out.push(tok("id", tx == "push_back" ? "push" : "pop", ln(tokens[i])));
                    i++;
                    stmtStart = false;
                    continue;
                }
            }

            // old Flixel setters: bf->setAlpha(0.5f) -> bf.alpha = 0.5
            if (kd == "id" && i + 1 < tokens.length && text(tokens[i + 1]) == "("
                && out.length > 0 && text(out[out.length - 1]) == ".") {
                var legacy = legacySetter(tx);
                if (legacy != null) {
                    var setterClose = matchParen(tokens, i + 1);
                    if (setterClose > 0) {
                        var setterArgs = sliceTokens(tokens, i + 2, setterClose);
                        var mappedIsCall = (legacy == "scrollFactor.set");
                        if (mappedIsCall || setterArgs.length > 0) {
                            var recvStart = receiverStart(out);
                            if (recvStart >= 0) {
                                var recv = sliceTokens(out, recvStart, out.length - 1);
                                while (out.length > recvStart) out.pop();
                                pushAll(out, recv);
                                var mapped = legacy.split(".");
                                var mk = 0;
                                while (mk < mapped.length) {
                                    out.push(tok("op", ".", ln(tokens[i])));
                                    out.push(tok("id", mapped[mk], ln(tokens[i])));
                                    mk++;
                                }
                                if (mappedIsCall) {
                                    out.push(tok("op", "(", ln(tokens[i])));
                                    pushAll(out, rewriteExpression(setterArgs, macros, includes));
                                    out.push(tok("op", ")", ln(tokens[i])));
                                } else {
                                    out.push(tok("op", "=", ln(tokens[i])));
                                    pushAll(out, rewriteExpression(setterArgs, macros, includes));
                                }
                                i = setterClose + 1;
                                stmtStart = false;
                                continue;
                            }
                        }
                    }
                }
            }

            // `case X:` / `default:` start a new statement
            if (tx == ":" && isCaseLabel(out)) {
                out.push(t);
                i++;
                stmtStart = true;
                continue;
            }

            // expression level rewrites
            var ex:Dynamic = exprRewrite(tokens, i, macros, includes);
            if (ex != null) {
                pushAll(out, ex.tokens);
                i = ex.end;
                stmtStart = false;
                continue;
            }

            out.push(t);
            i++;
            stmtStart = false;
        }
        return out;
    }

    // =====================================================================
    // DECLARATIONS
    // =====================================================================

    static function tryDeclaration(tokens:Array<Dynamic>, start:Int, macros:Array<Dynamic>, includes:Array<String>):Dynamic {
        var n = tokens.length;
        var i = start;
        var quals = qualifierList();
        while (i < n && kindOf(tokens[i]) == "id"
            && (quals.indexOf(text(tokens[i])) >= 0 || text(tokens[i]) == "unsigned" || text(tokens[i]) == "signed")) i++;
        if (i >= n || kindOf(tokens[i]) != "id") return null;

        // find the head of the statement
        var j = i;
        var depth = 0;
        var headIdx = -1;
        var headTok = "";
        while (j < n) {
            var c = text(tokens[j]);
            if (c == "(") {
                if (depth == 0) {
                    headIdx = j;
                    headTok = "(";
                    break;
                }
                depth++;
                j++;
                continue;
            }
            if (c == "[" || c == "<") {
                depth++;
                j++;
                continue;
            }
            if (c == ")" || c == "]" || c == ">") {
                depth--;
                j++;
                continue;
            }
            if (c == ">>") {
                depth -= 2;
                j++;
                continue;
            }
            if (c == "<<" ) {
                depth += 2;
                j++;
                continue;
            }
            if (depth <= 0 && (c == "=" || c == ";" || c == "," || c == "{")) {
                headIdx = j;
                headTok = c;
                break;
            }
            j++;
        }
        if (headIdx < 0) return null;

        if (headTok == "(") return declarationFromParen(tokens, i, headIdx, macros, includes);

        // ---- variable declaration ----
        var nameIdx = headIdx - 1;
        if (nameIdx <= i) return null; // single identifier -> assignment / call
        if (kindOf(tokens[nameIdx]) != "id") return null;
        if (text(tokens[nameIdx - 1]) == ".") return null; // member access, not a declaration

        var ids = 0;
        var k = i;
        while (k < nameIdx) {
            if (kindOf(tokens[k]) == "id") ids++;
            else if (kindOf(tokens[k]) == "op" && text(tokens[k]) != "." && !isTypeOperator(text(tokens[k]))) return null;
            k++;
        }
        if (ids < 1) return null;
        if (kindOf(tokens[i]) != "id") return null;

        // find the end of the statement
        var stmtEnd = headIdx;
        var d = 0;
        while (stmtEnd < n) {
            var c = text(tokens[stmtEnd]);
            // only real groups count: `<`/`>` here are comparisons, not templates
            if (c == "(" || c == "[" || c == "{") d++;
            else if (c == ")" || c == "]" || c == "}") d--;
            if (c == ";" && d <= 0) break;
            stmtEnd++;
        }
        if (stmtEnd >= n) return null;

        var parts = splitTopLevel(sliceTokens(tokens, nameIdx, stmtEnd), ",");
        var res:Array<Dynamic> = [];
        var pi = 0;
        while (pi < parts.length) {
            var part:Array<Dynamic> = parts[pi];
            if (part.length == 0) return null;
            var eq = topLevelIndex(part, "=");
            var nameEnd = (eq >= 0) ? eq : part.length;
            var nm = lastId(part, 0, nameEnd);
            if (nm == null) return null;
            res.push(tok("id", "var", ln(tokens[nameIdx])));
            res.push(tok("id", nm, ln(tokens[nameIdx])));
            if (eq >= 0) {
                pushAll(res, rewriteValue(sliceTokens(part, eq, part.length), macros, includes));
            } else if (hasId(tokens, i, nameIdx, "vector")) {
                // an uninitialized std::vector is an empty array
                res.push(tok("op", "=", ln(tokens[nameIdx])));
                res.push(tok("op", "[", ln(tokens[nameIdx])));
                res.push(tok("op", "]", ln(tokens[nameIdx])));
            }
            res.push(tok("op", ";", ln(tokens[nameIdx])));
            pi++;
        }
        return {tokens: res, end: stmtEnd + 1, drop: false, stmtStart: true};
    }

    /** A value with a block (lambda body, object literal...) needs statement rewriting. */
    static function rewriteValue(toks:Array<Dynamic>, macros:Array<Dynamic>, includes:Array<String>):Array<Dynamic> {
        for (t in toks) if (text(t) == "{") return rewrite(toks, macros, includes);
        return rewriteExpression(toks, macros, includes);
    }

    static function declarationFromParen(tokens:Array<Dynamic>, i:Int, headIdx:Int, macros:Array<Dynamic>, includes:Array<String>):Dynamic {
        var n = tokens.length;
        var nameIdx = headIdx - 1;
        if (nameIdx < i) return null;
        if (kindOf(tokens[nameIdx]) != "id") return null;
        var name = text(tokens[nameIdx]);
        if (nameIdx > i && text(tokens[nameIdx - 1]) == ".") return null; // obj.method(...)
        var hasPrefix = nameIdx > i;

        var closeIdx = matchParen(tokens, headIdx);
        if (closeIdx < 0) return null;

        var after = closeIdx + 1;
        while (after < n && kindOf(tokens[after]) == "id"
            && (text(tokens[after]) == "const" || text(tokens[after]) == "noexcept"
                || text(tokens[after]) == "override" || text(tokens[after]) == "final")) after++;

        var isCtorInit = after < n && text(tokens[after]) == ":";
        if (isCtorInit) {
            while (after < n && text(tokens[after]) != "{") after++;
        }
        var isDef = after < n && text(tokens[after]) == "{";
        var isProto = after < n && text(tokens[after]) == ";";
        if (!hasPrefix && !isDef) return null; // call statement
        if (hasPrefix && !isDef && !isProto) return null;

        if (isProto) return {tokens: [], end: after + 1, drop: true, stmtStart: true};

        var res:Array<Dynamic> = [];
        res.push(tok("id", "function", ln(tokens[nameIdx])));
        res.push(tok("id", name, ln(tokens[nameIdx])));
        res.push(tok("op", "(", ln(tokens[nameIdx])));
        pushAll(res, convertParams(tokens, headIdx + 1, closeIdx, macros, includes));
        res.push(tok("op", ")", ln(tokens[nameIdx])));
        return {tokens: res, end: after, drop: false, stmtStart: false};
    }

    static function convertParams(tokens:Array<Dynamic>, from:Int, to:Int, macros:Array<Dynamic>, includes:Array<String>):Array<Dynamic> {
        var raw = sliceTokens(tokens, from, to);
        var parts = splitTopLevel(raw, ",");
        var params:Array<Dynamic> = [];
        var i = 0;
        while (i < parts.length) {
            var p:Dynamic = paramOf(parts[i], macros, includes);
            if (p != null) params.push(p);
            i++;
        }
        if (params.length == 1 && text(params[0][0]) == "void") return [];

        var res:Array<Dynamic> = [];
        var paramLn = (from < tokens.length) ? ln(tokens[from]) : 1;
        var k = 0;
        while (k < params.length) {
            if (k > 0) res.push(tok("op", ",", paramLn));
            var pt:Array<Dynamic> = params[k];
            for (q in pt) res.push([q[0], q[1], paramLn]);
            k++;
        }
        return res;
    }

    static function paramOf(toks:Array<Dynamic>, macros:Array<Dynamic>, includes:Array<String>):Array<Dynamic> {
        if (toks.length == 0) return null;
        var quals = qualifierList();
        var startI = 0;
        while (startI < toks.length && kindOf(toks[startI]) == "id" && quals.indexOf(text(toks[startI])) >= 0) startI++;
        if (startI >= toks.length) return null;

        var eq = topLevelIndex(toks, "=");
        var nameEnd = (eq >= 0) ? eq : toks.length;
        var nm = lastId(toks, startI, nameEnd);
        if (nm == null) return null;
        if (nm == "void" && eq < 0) return [tok("id", "void", ln(toks[startI]))];

        var res:Array<Dynamic> = [tok("id", nm, ln(toks[startI]))];
        if (eq >= 0) pushAll(res, rewriteExpression(sliceTokens(toks, eq, toks.length), macros, includes));
        return res;
    }

    static function hasId(tokens:Array<Dynamic>, from:Int, to:Int, name:String):Bool {
        var i = from;
        while (i < to && i < tokens.length) {
            if (kindOf(tokens[i]) == "id" && text(tokens[i]) == name) return true;
            i++;
        }
        return false;
    }

    static function sliceTokens(tokens:Array<Dynamic>, from:Int, to:Int):Array<Dynamic> {
        var res:Array<Dynamic> = [];
        var i = from;
        while (i < to && i < tokens.length) {
            res.push(tokens[i]);
            i++;
        }
        return res;
    }

    // =====================================================================
    // FOR LOOPS
    // =====================================================================

    /** `{a, b}` (C++ initializer list) -> `[a, b]` (HScript array). */
    static function braceList(toks:Array<Dynamic>):Array<Dynamic> {
        var res:Array<Dynamic> = [];
        var i = 0;
        while (i < toks.length) {
            if (i == 0) res.push(tok("op", "[", ln(toks[i])));
            else if (i == toks.length - 1) res.push(tok("op", "]", ln(toks[i])));
            else res.push(toks[i]);
            i++;
        }
        return res;
    }

    static function convertFor(tokens:Array<Dynamic>, start:Int, closeIdx:Int, macros:Array<Dynamic>, includes:Array<String>):Array<Dynamic> {
        var inner = sliceTokens(tokens, start + 2, closeIdx);
        var lnv = ln(tokens[start]);

        // range based: for (auto& note : notes)
        var colon = topLevelIndex(inner, ":");
        if (colon >= 0) {
            // for (auto& [key, value] : map) -> for (key => value in map)
            var pair = structuredBindingNames(inner, colon);
            var nm = pair != null ? pair[1] : lastId(inner, 0, colon);
            if (nm == null || nm == "void") return null;
            var res:Array<Dynamic> = [];
            res.push(tok("id", "for", lnv));
            res.push(tok("op", "(", lnv));
            res.push(tok("id", pair != null ? pair[0] : nm, lnv));
            if (pair != null) {
                res.push(tok("op", "=>", lnv));
                res.push(tok("id", nm, lnv));
            }
            res.push(tok("id", "in", lnv));
            var range = sliceTokens(inner, colon + 1, inner.length);
            // for (auto& i : {bf, dad})  ->  for (i in [bf, dad])
            if (range.length >= 2 && text(range[0]) == "{" && text(range[range.length - 1]) == "}") {
                range = braceList(range);
            }
            pushAll(res, rewriteExpression(range, macros, includes));
            res.push(tok("op", ")", lnv));
            return res;
        }

        var parts = splitTopLevel(inner, ";");
        if (parts.length != 3) return null;

        // init: [type] name = value
        var init:Array<Dynamic> = parts[0];
        var eq = topLevelIndex(init, "=");
        if (eq < 0) return null;
        var nm = lastId(init, 0, eq);
        if (nm == null) return null;

        // condition: name < value  /  name <= value
        var cond:Array<Dynamic> = parts[1];
        if (cond.length < 3) return null;
        if (text(cond[0]) != nm) return null;
        var op = text(cond[1]);
        if (op != "<" && op != "<=") return null;

        // increment: name++ / ++name / name += 1
        var incr:Array<Dynamic> = parts[2];
        var ok = false;
        if (incr.length == 2 && text(incr[0]) == nm && text(incr[1]) == "++") ok = true;
        if (incr.length == 2 && text(incr[1]) == nm && text(incr[0]) == "++") ok = true;
        if (incr.length == 3 && text(incr[0]) == nm && text(incr[1]) == "+=" && text(incr[2]) == "1") ok = true;
        if (incr.length == 5 && text(incr[0]) == nm && text(incr[1]) == "="
            && text(incr[2]) == nm && text(incr[3]) == "+" && text(incr[4]) == "1") ok = true;
        if (!ok) return null;

        var res:Array<Dynamic> = [];
        res.push(tok("id", "for", lnv));
        res.push(tok("op", "(", lnv));
        res.push(tok("id", nm, lnv));
        res.push(tok("id", "in", lnv));
        pushAll(res, rewriteExpression(sliceTokens(init, eq + 1, init.length), macros, includes));
        res.push(tok("op", "...", lnv));
        if (op == "<=") res.push(tok("op", "(", lnv));
        pushAll(res, rewriteExpression(sliceTokens(cond, 2, cond.length), macros, includes));
        if (op == "<=") {
            res.push(tok("op", "+", lnv));
            res.push(tok("num", "1", lnv));
            res.push(tok("op", ")", lnv));
        }
        res.push(tok("op", ")", lnv));
        return res;
    }

    // =====================================================================
    // EXPRESSION REWRITES
    // =====================================================================

    static function exprRewrite(tokens:Array<Dynamic>, i:Int, macros:Array<Dynamic>, includes:Array<String>):Dynamic {
        var t = tokens[i];
        var tx = text(t);
        var lnv = ln(t);
        var n = tokens.length;

        // fully qualified engine names: funkin::game::PlayState::instance -> PlayState.instance
        if (kindOf(t) == "id" && isPackageRoot(tx) && i + 1 < n && text(tokens[i + 1]) == ".") {
            var seq:Array<String> = [];
            var seqEnds:Array<Int> = [];
            var pos = i;
            while (pos < n && kindOf(tokens[pos]) == "id") {
                seq.push(text(tokens[pos]));
                pos++;
                seqEnds.push(pos);
                if (pos < n && text(tokens[pos]) == "." && pos + 1 < n && kindOf(tokens[pos + 1]) == "id") pos++;
                else break;
            }

            var matchLen = 0;
            var k = seq.length;
            while (k >= 2) {
                if (includes.indexOf(joinDots(seq, k)) >= 0) {
                    matchLen = k;
                    break;
                }
                k--;
            }
            if (matchLen == 0) {
                var m = 1;
                while (m < seq.length) {
                    if (isUpperStart(seq[m])) {
                        matchLen = m + 1;
                        break;
                    }
                    m++;
                }
            }
            if (matchLen == 0) matchLen = 1;

            // only replace the class part; the members after it keep going through the
            // normal rewrites (setters, macros, casts...)
            return {tokens: [tok("id", seq[matchLen - 1], lnv)], end: seqEnds[matchLen - 1]};
        }

        // static_cast<float>(x) / dynamic_cast<Foo*>(x) / ...
        if ((tx == "static_cast" || tx == "dynamic_cast" || tx == "reinterpret_cast" || tx == "const_cast")
            && i + 1 < n && text(tokens[i + 1]) == "<") {
            var j = i + 1;
            var depth = 0;
            while (j < n) {
                var c = text(tokens[j]);
                if (c == "<") depth++;
                else if (c == ">") {
                    depth--;
                    if (depth == 0) {
                        j++;
                        break;
                    }
                }
                j++;
            }
            // static_cast<int>(x) -> Std.int(x);  float casts are just parentheses
            var typeName = "";
            var tk = i + 2;
            while (tk < n && tk < j - 1) {
                if (kindOf(tokens[tk]) == "id") typeName = text(tokens[tk]);
                tk++;
            }
            var intLike = typeName == "int" || typeName == "long" || typeName == "short"
                || typeName == "size_t" || typeName == "unsigned" || typeName == "uint";
            if (intLike && j < n && text(tokens[j]) == "(") {
                return {tokens: [tok("id", "Std.int", lnv)], end: j};
            }
            return {tokens: [], end: j};
        }

        // std::string / std::vector / std::floor / std::whatever
        if (tx == "std" && i + 1 < n && text(tokens[i + 1]) == ".") {
            var next = (i + 2 < n) ? text(tokens[i + 2]) : "";
            if (next == "string") return {tokens: [tok("id", "String", lnv)], end: i + 3};
            if (next == "vector") return {tokens: [tok("id", "Array", lnv)], end: i + 3};
            if (next == "to_string") return {tokens: [tok("id", "Std.string", lnv)], end: i + 3};
            var math = stdMathName(next);
            if (math != null) return {tokens: [tok("id", math, lnv)], end: i + 3};
            return {tokens: [], end: i + 2};
        }

        if (tx == "nullptr" || tx == "NULL") return {tokens: [tok("id", "null", lnv)], end: i + 1};
        if (tx == "and") return {tokens: [tok("op", "&&", lnv)], end: i + 1};
        if (tx == "or") return {tokens: [tok("op", "||", lnv)], end: i + 1};
        if (tx == "not") return {tokens: [tok("op", "!", lnv)], end: i + 1};

        // std::vector helpers fuera del bucle principal: `for (int i = 0; i < v.size(); i++)`
        // y `int n = v.size();` pasan por aqui, no por rewrite()
        if ((tx == "size" || tx == "push_back" || tx == "pop_back")
            && i > 0 && text(tokens[i - 1]) == "." && i + 1 < n && text(tokens[i + 1]) == "(") {
            var vecClose = matchParen(tokens, i + 1);
            if (vecClose > 0) {
                if (tx == "size") return {tokens: [tok("id", "length", lnv)], end: vecClose + 1};
                return {tokens: [tok("id", tx == "push_back" ? "push" : "pop", lnv)], end: i + 1};
            }
        }

        // sizeof(...) -> 0
        if (tx == "sizeof" && i + 1 < n && text(tokens[i + 1]) == "(") {
            var close = matchParen(tokens, i + 1);
            if (close > 0) return {tokens: [tok("num", "0", lnv)], end: close + 1};
        }

        // C style cast of a single primitive type: (float)x
        if (tx == "(" && i + 2 < n && kindOf(tokens[i + 1]) == "id" && text(tokens[i + 2]) == ")") {
            var inner = text(tokens[i + 1]);
            if (isPrimitiveType(inner)) {
                return {tokens: [], end: i + 3};
            }
        }

        // compile time constants
        var mv = macroValue(macros, tx);
        if (mv != null) {
            var mt = tokenize(mv);
            var k = 0;
            while (k < mt.length) {
                mt[k][2] = lnv;
                k++;
            }
            return {tokens: mt, end: i + 1};
        }
        return null;
    }

    // =====================================================================
    // CONSOLE OUTPUT
    // =====================================================================

    static function isCoutChain(tokens:Array<Dynamic>, i:Int):Bool {
        if (i >= tokens.length) return false;
        var tx = text(tokens[i]);
        if (tx == "cout" || tx == "cerr" || tx == "clog")
            return i + 1 < tokens.length && text(tokens[i + 1]) == "<<";
        if (tx == "std" && i + 3 < tokens.length && text(tokens[i + 1]) == ".") {
            var name = text(tokens[i + 2]);
            if (name == "cout" || name == "cerr" || name == "clog") return text(tokens[i + 3]) == "<<";
        }
        return false;
    }

    static function isStreamName(part:Array<Dynamic>):Bool {
        if (part.length == 1 && kindOf(part[0]) == "id") {
            var t = text(part[0]);
            return t == "cout" || t == "cerr" || t == "clog";
        }
        if (part.length == 3 && text(part[0]) == "std" && text(part[1]) == ".") {
            var t = text(part[2]);
            return t == "cout" || t == "cerr" || t == "clog";
        }
        return false;
    }

    static function isNewlinePart(part:Array<Dynamic>):Bool {
        if (part.length == 1) {
            if (kindOf(part[0]) == "id" && text(part[0]) == "endl") return true;
            if (kindOf(part[0]) == "str") {
                var s = text(part[0]);
                return s == "\"\\n\"" || s == "\"\\r\\n\"";
            }
        }
        if (part.length == 3 && text(part[0]) == "std" && text(part[1]) == "." && text(part[2]) == "endl") return true;
        return false;
    }

    static function printfTokens(kind:String, args:Array<Dynamic>, macros:Array<Dynamic>, includes:Array<String>, lnv:Int):Array<Dynamic> {
        var res:Array<Dynamic> = [tok("id", "trace", lnv), tok("op", "(", lnv)];

        var parts:Array<Dynamic> = null;
        if (kind == "printf" && args.length > 0 && args[0].length == 1 && kindOf(args[0][0]) == "str") {
            var fmt = text(args[0][0]);
            if (fmt.length >= 2) {
                var inner = fmt.substring(1, fmt.length - 1);
                parts = splitFormat(inner, args.length - 1);
            }
        }

        if (parts == null) {
            var k = 0;
            while (k < args.length) {
                if (k > 0) res.push(tok("op", ",", lnv));
                pushAll(res, rewriteExpression(args[k], macros, includes));
                k++;
            }
        } else {
            var written = 0;
            var p = 0;
            while (p < parts.length) {
                var part:Dynamic = parts[p];
                p++;
                if (written > 0) res.push(tok("op", "+", lnv));
                if (part[0] == "str") {
                    res.push(tok("str", "\"" + part[1] + "\"", lnv));
                } else {
                    res.push(tok("id", "Std", lnv));
                    res.push(tok("op", ".", lnv));
                    res.push(tok("id", "string", lnv));
                    res.push(tok("op", "(", lnv));
                    var argIndex:Int = Std.int(part[1]) + 1;
                    if (argIndex < args.length) {
                        var argCode:Array<Dynamic> = args[argIndex];
                        pushAll(res, rewriteExpression(argCode, macros, includes));
                    }
                    res.push(tok("op", ")", lnv));
                }
                written++;
            }
            if (written == 0) res.push(tok("str", "\"\"", lnv));
        }

        res.push(tok("op", ")", lnv));
        return res;
    }

    /** Splits a printf format string into literal chunks and argument references. */
    static function splitFormat(fmt:String, argCount:Int):Array<Dynamic> {
        var parts:Array<Dynamic> = [];
        var chunk = "";
        var argIndex = 0;
        var i = 0;
        while (i < fmt.length) {
            var c = fmt.charAt(i);
            if (c != "%") {
                chunk += c;
                i++;
                continue;
            }
            var j = i + 1;
            if (j < fmt.length && fmt.charAt(j) == "%") {
                chunk += "%";
                i = j + 1;
                continue;
            }
            while (j < fmt.length && isFormatFlag(fmt.charAt(j))) j++;
            if (j >= fmt.length) {
                chunk += "%";
                i++;
                continue;
            }
            var spec = fmt.charAt(j);
            if (isFormatSpec(spec)) {
                if (argIndex >= argCount) return null;
                if (chunk.length > 0) {
                    parts.push(["str", chunk]);
                    chunk = "";
                }
                parts.push(["arg", argIndex]);
                argIndex++;
                i = j + 1;
                continue;
            }
            chunk += "%" + spec;
            i = j + 1;
        }
        if (chunk.length > 0) parts.push(["str", chunk]);
        return parts;
    }

    static function isFormatFlag(c:String):Bool {
        return c == "-" || c == "+" || c == " " || c == "0" || c == "#" || c == "."
            || isDigit(c) || c == "l" || c == "h" || c == "L" || c == "z" || c == "j" || c == "t";
    }

    static function isFormatSpec(c:String):Bool {
        return c == "s" || c == "d" || c == "i" || c == "f" || c == "g" || c == "x" || c == "X"
            || c == "u" || c == "c" || c == "e" || c == "E" || c == "G" || c == "o" || c == "b";
    }

    static function legacySetter(name:String):String {
        if (name == "setAlpha") return "alpha";
        if (name == "setAngle") return "angle";
        if (name == "setX") return "x";
        if (name == "setY") return "y";
        if (name == "setColor") return "color";
        if (name == "setScrollFactor") return "scrollFactor.set";
        return null;
    }

    /** Finds where the receiver of a method call starts inside the emitted tokens. */
    static function receiverStart(out:Array<Dynamic>):Int {
        var last = out.length - 1; // the dot right before the setter name
        if (last < 1) return -1;
        var i = last - 1;
        while (i >= 0) {
            var c = text(out[i]);
            if (c == ")" || c == "]") {
                var open = (c == ")") ? "(" : "[";
                var depth = 0;
                var j = i;
                while (j >= 0) {
                    var t = text(out[j]);
                    if (t == c) depth++;
                    else if (t == open) {
                        depth--;
                        if (depth == 0) break;
                    }
                    j--;
                }
                if (j < 0) return -1;
                if (c == ")") {
                    var before = (j > 0) ? text(out[j - 1]) : "";
                    if (isControlWord(before)) return j + 1; // if (x) sprite.setAlpha -> receiver is sprite
                }
                var prev = (j > 0) ? text(out[j - 1]) : "";
                if (kindOf(out[j - 1]) != "id" && prev != ")" && prev != "]") return j;
                i = j - 1;
            } else if (kindOf(out[i]) == "id" || kindOf(out[i]) == "num" || kindOf(out[i]) == "str") {
                i--;
            } else {
                return -1;
            }
            if (i >= 0 && text(out[i]) == ".") {
                i--;
                continue;
            }
            break;
        }
        return i + 1;
    }

    static function isControlWord(w:String):Bool {
        if (w == "return" || w == "else") return true;
        return keywordList().indexOf(w) >= 0;
    }

    static function isTypeOperator(c:String):Bool {
        return c == "." || c == "*" || c == "&" || c == "<" || c == ">" || c == ">>" || c == "[" || c == "]"
            || c == "::" || c == ",";
    }

    static function rewriteExpression(list:Array<Dynamic>, macros:Array<Dynamic>, includes:Array<String>):Array<Dynamic> {
        var out:Array<Dynamic> = [];
        var i = 0;
        while (i < list.length) {
            var ex:Dynamic = exprRewrite(list, i, macros, includes);
            if (ex != null) {
                pushAll(out, ex.tokens);
                i = ex.end;
                continue;
            }
            out.push(list[i]);
            i++;
        }
        return out;
    }

    static function isPackageRoot(name:String):Bool {
        return name == "funkin" || name == "flixel" || name == "lime" || name == "openfl"
            || name == "animate" || name == "hscript" || name == "haxe";
    }

    static function isUpperStart(name:String):Bool {
        if (name.length == 0) return false;
        var code = name.charCodeAt(0);
        return code >= 65 && code <= 90;
    }

    static function joinDots(list:Array<String>, count:Int):String {
        var res = "";
        var i = 0;
        while (i < count) {
            if (i > 0) res += ".";
            res += list[i];
            i++;
        }
        return res;
    }

    static function isPrimitiveType(name:String):Bool {
        return name == "float" || name == "double" || name == "int" || name == "bool" || name == "char"
            || name == "void" || name == "long" || name == "short" || name == "uint" || name == "size_t"
            || name == "Float" || name == "Int" || name == "Bool";
    }

    // =====================================================================
    // OUTPUT
    // =====================================================================

    public static function emit(tokens:Array<Dynamic>):String {
        var buf = new StringBuf();
        var prev = "";
        var prevLine = -1;
        var i = 0;
        while (i < tokens.length) {
            var tx = text(tokens[i]);
            var lnv = ln(tokens[i]);
            if (prevLine >= 0 && lnv > prevLine && prev != "." && tx != ".") {
                var gap = lnv - prevLine;
                if (gap > 20) gap = 1; // keep line numbers sane on weird gaps
                while (gap > 0) {
                    buf.add("\n");
                    gap--;
                }
            } else if (prev.length > 0 && needsSpace(prev, tx)) {
                buf.add(" ");
            }
            buf.add(tx);
            prev = tx;
            prevLine = lnv;
            i++;
        }
        return buf.toString();
    }

    static function needsSpace(prev:String, cur:String):Bool {
        if (prev.length == 0) return false;
        if (cur == "," || cur == ";" || cur == ")" || cur == "]" || cur == "." || cur == "("
            || cur == "<" || cur == ">" || cur == ":" || cur == "?" || cur == "++" || cur == "--"
            || cur == "..." || cur == "[" || cur == "?." || cur == "<<" || cur == ">>") return false;
        if (prev == "(" || prev == "[" || prev == "." || prev == "<" || prev == ">" || prev == "!"
            || prev == "~" || prev == "++" || prev == "--" || prev == "?" || prev == "..."
            || prev == "?." || prev == "<<" || prev == ">>") return false;
        return true;
    }
}
