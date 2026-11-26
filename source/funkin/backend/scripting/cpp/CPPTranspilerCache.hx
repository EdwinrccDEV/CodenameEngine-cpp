package funkin.backend.scripting.cpp;

/**
 * Cache de fragmentos ya transpilados (las cabeceras `.hpp` incluidas).
 *
 * Vive fuera del transpilador: incluir una misma cabecera en varios scripts
 * solo cuesta una transformacion por sesion.
 */
class CPPTranspilerCache {
    /** Sube esto al cambiar la sintaxis o el codigo generado: invalida la cache. */
    public static inline var VERSION:String = "4";

    /** hash del script -> HScript completo (con su cabecera de imports). */
    static var code:Map<String, String> = [];
    /** hash del .hpp + macros -> fragmento ya transpilado (sin directivas). */
    static var fragments:Map<String, String> = [];

    public static var hits:Int = 0;
    public static var misses:Int = 0;

    public static function getCode(key:String):String {
        if (key == null || !code.exists(key)) return null;
        return code.get(key);
    }

    public static function setCode(key:String, value:String) {
        if (key != null) code.set(key, value);
    }

    public static function getFragment(key:String):String {
        if (key == null || !fragments.exists(key)) return null;
        return fragments.get(key);
    }

    public static function setFragment(key:String, value:String) {
        if (key != null) fragments.set(key, value);
    }

    public static function clear() {
        // Vacia los Map en sitio en vez de reasignar `[]`: cuando esto se llama
        // desde un script (por ejemplo `CPPCompiler.clearCache()`), un `[]`
        // literal puede acabar siendo un Array vacio en vez de un Map, y
        // entonces `getCode`/`setCode` revientan con Null Function Pointer.
        code.clear();
        fragments.clear();
        hits = 0;
        misses = 0;
    }

    /** Hash rápido (FNV-1a x2 -> 64 bits en hex). Mucho mas barato que Sha1,
     *  que en algunos targets cuesta mas que compilar el script entero. */
    public static function hash(s:String):String {
        // Solo sumas, multiplicaciones y modulo con valores pequenos: en HScript
        // los literales mayores que 2^31 y los operadores de bits (>>>) no se
        // comportan igual en todos los targets, y el hash acababa devolviendo
        // la MISMA clave para todos los scripts (cache envenenada).
        var h1 = 5381;
        var h2 = 52711;
        var i = 0;
        while (i < s.length) {
            var c = s.charCodeAt(i);
            h1 = (h1 * 31 + c) % 999983;
            h2 = (h2 * 61 + c) % 999979;
            i++;
        }
        return h1 + "_" + h2 + "_" + s.length;
    }
}
