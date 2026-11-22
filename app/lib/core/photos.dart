// The person's own photos for the vision board (PLAN 13): made small on the device and kept inside the encrypted app
// data, so they are encrypted at rest and travel only inside the locked transfer file. No photo ever leaves otherwise.
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

const photoWidth = 720; // enough for a card on any screen, small enough to keep saving quick
// Limits (security review 2026-11-14, F-14): a photo file above 30 MB, or above 50 megapixels, is refused before it
// is decoded, as decoding a 30,000 x 30,000 picture just to read its size needs gigabytes.
const maxPhotoBytes = 30 * 1024 * 1024, maxPhotoPixels = 50 * 1000 * 1000;

/// [bytes] of any image the platform can read, as a PNG at most [photoWidth] wide (base64), or null if unreadable or
/// too large. The size is read from the file's header, without decoding the picture.
Future<String?> shrinkPhoto(Uint8List bytes) async {
  if (bytes.length > maxPhotoBytes) return null;
  ui.ImmutableBuffer? buffer;
  ui.ImageDescriptor? descriptor;
  try {
    buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    final w = descriptor.width, h = descriptor.height;
    if (w <= 0 || h <= 0 || w * h > maxPhotoPixels) return null;
    final codec = await descriptor.instantiateCodec(targetWidth: w > photoWidth ? photoWidth : w);
    final image = (await codec.getNextFrame()).image;
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    codec.dispose();
    return png == null ? null : base64Encode(png.buffer.asUint8List());
  } catch (_) {
    return null;
  } finally {
    descriptor?.dispose();
    buffer?.dispose();
  }
}

/// Limits for a picture Solace will draw (OWASP review OW-M4-1: the engine decodes a PNG at full size before shrinking
/// it, so a 12,000 x 12,000 picture in a transfer file would need gigabytes every time Today showed it). Every picture
/// Solace makes is at most 720 wide; these leave room for older ones and nothing more.
const maxPictureWidth = 1440, maxPictureHeight = 4000, maxPicturePixels = 4 * 1000 * 1000;

/// (width, height) read from a PNG's or JPEG's header without decoding it, or null if it is neither.
(int, int)? pictureDimensions(List<int> b) {
  int u16(int i) => (b[i] << 8) | b[i + 1];
  int u32(int i) => (b[i] << 24) | (b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3];
  if (b.length >= 24 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47 &&
      b[12] == 0x49 && b[13] == 0x48 && b[14] == 0x44 && b[15] == 0x52) {
    return (u32(16), u32(20));
  }
  if (b.length >= 4 && b[0] == 0xFF && b[1] == 0xD8) {
    var i = 2;
    for (var guard = 0; guard < 10000 && i + 9 < b.length; guard++) {
      if (b[i] != 0xFF) return null;
      final m = b[i + 1];
      if (m == 0xFF) { // fill byte
        i++;
        continue;
      }
      final sof = (m >= 0xC0 && m <= 0xC3) || (m >= 0xC5 && m <= 0xC7) || (m >= 0xC9 && m <= 0xCB) ||
          (m >= 0xCD && m <= 0xCF);
      if (sof) return (u16(i + 7), u16(i + 5));
      if (m == 0xD9 || m == 0xDA) return null; // end, or image data before any size
      i += 2 + u16(i + 2);
    }
  }
  return null;
}

/// Whether a stored or received picture is small enough to draw.
bool pictureFits(List<int> bytes) {
  final d = pictureDimensions(bytes);
  return d != null && d.$1 > 0 && d.$2 > 0 && d.$1 <= maxPictureWidth && d.$2 <= maxPictureHeight &&
      d.$1 * d.$2 <= maxPicturePixels;
}
