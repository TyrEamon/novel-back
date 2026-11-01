# PDFBox's JPX codec is an optional JCenter-only dependency. The importer
# rejects JPX images explicitly before decoding; other PDF filters stay live.
-dontwarn com.gemalto.jp2.JP2Decoder
-dontwarn com.gemalto.jp2.JP2Encoder

# POI HWPF reads binary Word text/raster bytes only. Java2D metafile geometry
# and GenericRecord JSON/debug rendering are desktop-only, not reader paths.
-dontwarn java.awt.**
# Log4j's optional OSGi discovery and compile-time annotations are not an
# Android logging backend; the API falls back to its built-in simple logger.
-dontwarn org.osgi.framework.**
-dontwarn aQute.bnd.annotation.**
-dontwarn edu.umd.cs.findbugs.annotations.**

# The book-source rule engine runs user-imported legado rules through the
# bundled Rhino runtime; its desktop-only converters reference JDK beans and
# XML APIs that Android does not ship, and R8 must not prune the script host.
-dontwarn java.beans.**
-dontwarn javax.**
-dontwarn org.w3c.dom.**
-dontwarn org.xml.sax.**
-keep class org.htmlunit.corejs.** { *; }
-keep class org.mewx.wenku8_flutter.legado.** { *; }
-keep class org.mewx.wenku8_flutter.sourceinternal.** { *; }
-keep class org.mewx.wenku8_flutter.BookSourceEngine { *; }
-keep class com.jayway.jsonpath.** { *; }
-keep class cn.wanghaomiao.** { *; }
-keep class cn.hutool.** { *; }

# JsonPath picks its JSON provider at runtime; every optional provider (Jackson,
# JsonOrg, JsonSmart, Groovy, SLF4J bridges) is absent on Android and unused.
-dontwarn com.jayway.jsonpath.**
-dontwarn com.fasterxml.jackson.**
-dontwarn org.codehaus.groovy.**
-dontwarn groovy.**
-dontwarn net.minidev.**
-dontwarn org.json.**
-dontwarn org.slf4j.**
-dontwarn org.apache.commons.logging.**
-dontwarn java.lang.management.**
-dontwarn jakarta.**
