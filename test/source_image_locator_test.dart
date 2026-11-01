import 'package:flutter_test/flutter_test.dart';
import 'package:wenku8_flutter/reader_content.dart';
import 'package:wenku8_flutter/sources/source_image_locator.dart';

void main() {
  test('image request options survive round trip without URI normalization', () {
    const raw =
        'https://fixture.invalid/image.jpg , {"headers":{"Referer":"https://fixture.invalid/chapter"}}';
    final locator = sourceImageLocator(
      42,
      raw,
      referrer: 'https://fixture.invalid/c1',
    )!;
    expect(Uri.parse(locator).queryParameters['url'], raw);
    expect(readerIllustrationUrl('<!--image-->$locator<!--image-->'), locator);
    expect(
      Uri.parse(locator).queryParameters['ref'],
      'https://fixture.invalid/c1',
    );
  });

  test(
    'inline base64 illustrations are accepted by both bridge and reader',
    () {
      const raw = 'data:image/png;base64,AQIDBA==';
      final locator = sourceImageLocator(42, raw)!;
      expect(
        readerIllustrationUrl('<!--image-->$locator<!--image-->'),
        locator,
      );
    },
  );

  test(
    'invalid schemes, credentials, book IDs and non-image data are rejected',
    () {
      for (final raw in [
        'javascript:alert(1)',
        'file:///private/file',
        'https://user:pass@fixture.invalid/image.jpg',
        'data:text/html;base64,PHN2Zz4=',
        'data:image/svg+xml;base64,PHN2Zz4=',
      ]) {
        expect(sourceImageLocator(42, raw), isNull);
      }
      expect(
        sourceImageLocator(0, 'https://fixture.invalid/image.jpg'),
        isNull,
      );
    },
  );
}
