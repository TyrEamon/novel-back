package org.mewx.wenku8_flutter

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import java.io.File

/** Normalize once on the document IO executor, not during reading/scrolling.
 * The original gallery file is never edited; alpha and EXIF orientation survive. */
internal object ReaderBackgroundImage {
    const val MAX_BYTES = 32L * 1024 * 1024
    const val MAX_EDGE = 2560

    fun sampleSize(width: Int, height: Int): Int {
        require(width in 1..65535 && height in 1..65535) { "图片尺寸无效，请换一张图片" }
        var sample = 1
        while (width / sample > MAX_EDGE || height / sample > MAX_EDGE) sample *= 2
        return sample
    }

    fun normalize(source: File, target: File) {
        require(source.length() in 1..MAX_BYTES) { "背景图片需要在 32 MiB 以内" }
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(source.path, bounds)
        val options = BitmapFactory.Options().apply {
            inSampleSize = sampleSize(bounds.outWidth, bounds.outHeight)
            inPreferredConfig = Bitmap.Config.ARGB_8888
        }
        val bitmap = BitmapFactory.decodeFile(source.path, options)
            ?: error("无法读取这张图片，请选择 JPG、PNG 或 WebP 图片")
        var oriented: Bitmap? = null
        try {
            val orientation = try {
                ExifInterface(source.path).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)
            } catch (_: Exception) { ExifInterface.ORIENTATION_NORMAL }
            val matrix = Matrix().apply {
                when (orientation) {
                    ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> setScale(-1f, 1f)
                    ExifInterface.ORIENTATION_ROTATE_180 -> setRotate(180f)
                    ExifInterface.ORIENTATION_FLIP_VERTICAL -> setScale(1f, -1f)
                    ExifInterface.ORIENTATION_TRANSPOSE -> { setRotate(90f); postScale(-1f, 1f) }
                    ExifInterface.ORIENTATION_ROTATE_90 -> setRotate(90f)
                    ExifInterface.ORIENTATION_TRANSVERSE -> { setRotate(-90f); postScale(-1f, 1f) }
                    ExifInterface.ORIENTATION_ROTATE_270 -> setRotate(-90f)
                }
            }
            oriented = if (matrix.isIdentity) bitmap else Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
            target.outputStream().use { output ->
                check(oriented.compress(Bitmap.CompressFormat.PNG, 100, output)) { "保存背景图片失败" }
                output.fd.sync()
            }
            require(target.length() in 1..MAX_BYTES) { "背景图片处理后仍过大，请换一张图片" }
        } catch (error: Exception) {
            target.delete()
            throw error
        } finally {
            if (oriented !== bitmap) oriented?.recycle()
            bitmap.recycle()
        }
    }
}
