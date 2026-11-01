package org.mewx.wenku8_flutter;

import android.app.Activity;
import android.app.Instrumentation;
import android.os.Bundle;
import java.io.File;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import org.json.JSONArray;
import org.json.JSONObject;

/** Read-only, explicitly selected cached-book audit. Never opens source/session
 * stores or prints URLs, image options, headers, scripts or account information. */
public final class ReaderContentAuditInstrumentation extends Instrumentation {
    private long bookId;
    private int chapterIndex;
    private boolean exportFixture;
    @Override public void onCreate(Bundle args) {
        super.onCreate(args);
        bookId = Long.parseLong(args.getString("bookId", "0"));
        chapterIndex = Integer.parseInt(args.getString("chapterIndex", "0"));
        exportFixture = !"false".equals(args.getString("exportFixture", "true"));
        start();
    }
    @Override public void onStart() {
        Bundle out = new Bundle();
        try {
            if (!getTargetContext().getPackageName().endsWith(".source_preview") || bookId <= 0 || chapterIndex < 0)
                throw new IllegalArgumentException();
            File folder = new File(getTargetContext().getFilesDir(), "wenku8-offline-v1/b" + bookId);
            File metadata = new File(folder, "book.json");
            if (!metadata.isFile() || metadata.length() > 4*1024*1024) throw new IllegalStateException("no cached book");
            JSONObject book = new JSONObject(new String(Files.readAllBytes(metadata.toPath()), StandardCharsets.UTF_8));
            JSONArray chapters = book.getJSONArray("chapters");
            JSONObject chapter = chapters.getJSONObject(chapterIndex);
            File file = new File(folder, "c" + chapter.getInt("id") + ".txt");
            if (!file.isFile() || file.length() > 8*1024*1024) throw new IllegalStateException("no cached chapter");
            String body = new String(Files.readAllBytes(file.toPath()), StandardCharsets.UTF_8);
            JSONObject report = new JSONObject();
            report.put("chapterCount", chapters.length());
            report.put("chapterIndex", chapterIndex);
            report.put("bodyChars", body.length());
            report.put("paragraphs", body.split("\n\n", -1).length);
            JSONArray images = new JSONArray();
            StringBuffer fixture = new StringBuffer();
            Matcher matcher = Pattern.compile("<!--image-->(.*?)<!--image-->", Pattern.DOTALL).matcher(body);
            while (matcher.find()) {
                JSONObject image = new JSONObject();
                String locator = matcher.group(1);
                android.net.Uri uri = android.net.Uri.parse(locator);
                String url = "source-image".equals(uri.getScheme()) ? uri.getQueryParameter("url") : locator;
                image.put("locatorChars", locator.length());
                image.put("remoteChars", url == null ? 0 : url.length());
                android.net.Uri remote = url == null ? null : android.net.Uri.parse(url);
                image.put("remoteHasQuery", remote != null && remote.getEncodedQuery() != null);
                image.put("remoteHasFragment", remote != null && remote.getEncodedFragment() != null);
                image.put("remoteQueryContainsUrl", remote != null && remote.getEncodedQuery() != null && remote.getEncodedQuery().contains("url="));
                image.put("markdownClosingParen", url != null && url.trim().endsWith(")"));
                String left = body.substring(Math.max(0, matcher.start() - 300), matcher.start());
                String right = body.substring(matcher.end(), Math.min(body.length(), matcher.end() + 300));
                image.put("markdownPrefix", Pattern.compile("!\\[[^\\]\\n]*\\]\\(\\s*$").matcher(left).find());
                image.put("markdownSuffix", right.trim().startsWith(")"));
                image.put("tailShape", right.substring(0, Math.min(right.length(), 100)).replaceAll("[\\p{L}\\p{N}]", "x"));
                // The report contains structural diagnostics only. The separate
                // private fixture replaces every image locator before export.
                images.put(image);
                matcher.appendReplacement(fixture, Matcher.quoteReplacement("<!--image-->wenku-local://1610612736/img-" + images.length() + ".png<!--image-->"));
            }
            matcher.appendTail(fixture);
            report.put("images", images);
            if (exportFixture) {
                File cache = getTargetContext().getExternalCacheDir();
                if (cache == null) throw new IllegalStateException("fixture cache unavailable");
                cache.mkdirs();
                File exported = new File(cache, "reader-audit.txt");
                Files.write(exported.toPath(), fixture.toString().getBytes(StandardCharsets.UTF_8));
                report.put("fixturePath", exported.getAbsolutePath());
            }
            out.putString("stream", report.toString() + "\n");
            finish(Activity.RESULT_OK, out);
        } catch (Throwable failure) {
            String reason = failure.getMessage();
            if (!java.util.Arrays.asList("no cached book", "no cached chapter", "fixture cache unavailable").contains(reason)) reason = "";
            out.putString("stream", "CONTENT_AUDIT_FAILURE=" + failure.getClass().getSimpleName() + ":" + reason + "\n");
            finish(Activity.RESULT_CANCELED, out);
        }
    }
}
