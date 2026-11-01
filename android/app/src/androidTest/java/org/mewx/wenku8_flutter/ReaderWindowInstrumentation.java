package org.mewx.wenku8_flutter;

import android.app.Activity;
import android.app.Instrumentation;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ActivityInfo;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.media.ExifInterface;
import android.os.Build;
import android.os.Bundle;
import android.view.View;
import android.view.Window;
import android.view.WindowInsets;
import java.io.File;
import java.io.FileOutputStream;
import java.util.ArrayList;

/** Java-only boundary: test APKs must not call Kotlin stdlib default-argument
 * methods which R8 legitimately inlines out of the independent target APK. */
public class ReaderWindowInstrumentation extends Instrumentation {
    @Override public void onCreate(Bundle arguments) { super.onCreate(arguments); start(); }
    private static void require(boolean value, String message) { if (!value) throw new AssertionError(message); }
    private static void delete(File file) { File[] children = file.listFiles(); if (children != null) for (File child : children) delete(child); file.delete(); }
    @Override public void onStart() {
        Bundle result = new Bundle();
        int code = Activity.RESULT_CANCELED;
        Context context = getTargetContext();
        File root = new File(context.getCacheDir(), "reader-window-fixture");
        ArrayList<String> checks = new ArrayList<>();
        try {
            require(context.getPackageName().endsWith(".source_preview"), "Independent preview only");
            require(root.mkdirs() || root.isDirectory(), "Fixture directory");
            File input = new File(root, "large.png"), output = new File(root, "normalized.png");
            Bitmap original = Bitmap.createBitmap(1800, 3000, Bitmap.Config.ARGB_8888);
            original.eraseColor(0x884276B2);
            try (FileOutputStream stream = new FileOutputStream(input)) { require(original.compress(Bitmap.CompressFormat.PNG, 100, stream), "PNG fixture"); }
            original.recycle();
            ReaderBackgroundImage.INSTANCE.normalize(input, output);
            Bitmap image = BitmapFactory.decodeFile(output.getPath());
            require(image.getWidth() == 900 && image.getHeight() == 1500 && image.hasAlpha(), "Bounded alpha PNG"); image.recycle();
            require(input.isFile(), "Original retained"); checks.add("bounded-background-and-alpha");

            File rotated = new File(root, "rotated.jpg");
            Bitmap jpeg = Bitmap.createBitmap(100, 200, Bitmap.Config.ARGB_8888); jpeg.eraseColor(0xff8A9D77);
            try (FileOutputStream stream = new FileOutputStream(rotated)) { require(jpeg.compress(Bitmap.CompressFormat.JPEG, 95, stream), "JPEG fixture"); } jpeg.recycle();
            ExifInterface exif = new ExifInterface(rotated.getPath());
            exif.setAttribute(ExifInterface.TAG_ORIENTATION, Integer.toString(ExifInterface.ORIENTATION_ROTATE_90)); exif.saveAttributes();
            ReaderBackgroundImage.INSTANCE.normalize(rotated, output);
            image = BitmapFactory.decodeFile(output.getPath());
            require(image.getWidth() == 200 && image.getHeight() == 100, "EXIF orientation"); image.recycle(); checks.add("exif-orientation");
            File invalid = new File(root, "invalid.png"), rejected = new File(root, "invalid-output.png");
            try (FileOutputStream stream = new FileOutputStream(invalid)) { stream.write(new byte[]{1, 2, 3, 4}); }
            boolean rejectedImage = false;
            try { ReaderBackgroundImage.INSTANCE.normalize(invalid, rejected); } catch (Exception expected) { rejectedImage = true; }
            require(rejectedImage && !rejected.exists(), "Invalid image rejected"); checks.add("invalid-image-rejection");

            final Activity activity = startActivitySync(new Intent().setClassName(context.getPackageName(), "org.mewx.wenku8_flutter.MainActivity").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
            Thread.sleep(1500);
            final int originalOrientation = activity.getRequestedOrientation();
            try {
                for (final int orientation : new int[]{ActivityInfo.SCREEN_ORIENTATION_PORTRAIT, ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE}) {
                    runOnMainSync(() -> activity.setRequestedOrientation(orientation)); Thread.sleep(700);
                    for (final boolean hidden : new boolean[]{true, false, true}) {
                        runOnMainSync(() -> {
                            Window window = activity.getWindow();
                            ReaderWindowLayout.INSTANCE.apply(window);
                            if (Build.VERSION.SDK_INT >= 30) {
                                if (hidden) window.getInsetsController().hide(WindowInsets.Type.statusBars());
                                else window.getInsetsController().show(WindowInsets.Type.statusBars());
                            } else {
                                int flags = window.getDecorView().getSystemUiVisibility();
                                window.getDecorView().setSystemUiVisibility(hidden ? flags | View.SYSTEM_UI_FLAG_FULLSCREEN : flags & ~View.SYSTEM_UI_FLAG_FULLSCREEN);
                            }
                        });
                        Thread.sleep(350);
                        runOnMainSync(() -> {
                            Window window = activity.getWindow();
                            if (Build.VERSION.SDK_INT >= 28) require(window.getAttributes().layoutInDisplayCutoutMode == ReaderWindowLayout.INSTANCE.cutoutMode(Build.VERSION.SDK_INT), "Cutout policy");
                            int[] point = new int[2]; window.getDecorView().getLocationOnScreen(point);
                            require(point[1] == 0, "Decor letterbox: " + point[1]);
                            View content = activity.findViewById(android.R.id.content); content.getLocationOnScreen(point);
                            require(point[1] == 0, "Content letterbox: " + point[1]);
                            if (hidden && Build.VERSION.SDK_INT >= 30) require(!window.getDecorView().getRootWindowInsets().isVisible(WindowInsets.Type.statusBars()), "Status bars hidden");
                        });
                    }
                    checks.add("cutout-status-transition-" + orientation);
                }
            } finally {
                runOnMainSync(() -> {
                    activity.setRequestedOrientation(originalOrientation);
                    if (Build.VERSION.SDK_INT >= 30) activity.getWindow().getInsetsController().show(WindowInsets.Type.statusBars());
                    activity.finish();
                });
            }
            result.putString("stream", "READER_WINDOW_VERIFIED=" + checks.toString() + "\n"); result.putInt("checks", checks.size());
            code = Activity.RESULT_OK;
        } catch (Throwable failure) {
            result.putString("stream", "READER_WINDOW_FAILURE=" + failure.getClass().getSimpleName() + ":" + failure.getMessage() + "\n");
        } finally { delete(root); }
        finish(code, result);
    }
}
