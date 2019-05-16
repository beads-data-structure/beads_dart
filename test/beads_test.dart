import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:beads/beads.dart';

void main() {
  test(
      'Add a null and 0 to beads, also tests that number of bytes and number of elements isnot the same',
      () {
    final beads = BeadsSequence(length: 0);
    beads.add(null);
    expect(beads.buffer.asUint8List(), [2, 1, 15, 0]);
    beads.add(0);
    expect(beads.buffer.asUint8List(), [3, 2, 31, 0, 0]);
    beads.add(null);
    expect(beads.buffer.asUint8List(), [4, 3, 31, 0, 15, 0]);
    beads.add(null);
    expect(beads.buffer.asUint8List(), [3, 4, 31, 0, 255]);
  });

  test('Add 20x null to exapnd buffer', () {
    final beads = BeadsSequence(length: 8);
    for (var i = 0; i < 20; i++) {
      beads.add(null);
    }

    expect(beads.buffer.asUint8List(),
        [10, 20, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255]);
  });

  test('Add u8', () {
    final beads = BeadsSequence()..add(13);
    expect(beads.buffer.asUint8List(), [2, 1, 1, 13]);
  });

  test('Add i8', () {
    final beads = BeadsSequence()..add(-13);
    expect(beads.buffer.asUint8List(), [2, 1, 2, 243]);
  });

  test('Add u16', () {
    final beads = BeadsSequence()..add(313);
    expect(beads.buffer.asUint8List(), [3, 1, 3, 57, 1]);
  });

  test('Add i16', () {
    final beads = BeadsSequence()..add(-313);
    expect(beads.buffer.asUint8List(), [3, 1, 4, 199, 254]);
  });

  test('Add u32', () {
    final beads = BeadsSequence()..add(3 << 16);
    expect(beads.buffer.asUint8List(), [5, 1, 5, 0, 0, 3, 0]);
  });

  test('Add i32', () {
    final beads = BeadsSequence()..add(-3 << 16);
    expect(beads.buffer.asUint8List(), [5, 1, 6, 0, 0, 253, 255]);
  });
  test('Add u64', () {
    final beads = BeadsSequence()..add(3 << 33);
    expect(beads.buffer.asUint8List(), [9, 1, 8, 0, 0, 0, 0, 6, 0, 0, 0]);
  });
  test('Add i64', () {
    final beads = BeadsSequence()..add(-3 << 33);
    expect(
        beads.buffer.asUint8List(), [9, 1, 9, 0, 0, 0, 0, 250, 255, 255, 255]);
  });

  test('add different integers', () {
    final beads = BeadsSequence()
      ..add(13)
      ..add(-13)
      ..add(313)
      ..add(-313)
      ..add(3 << 16)
      ..add(-3 << 16)
      ..add(3 << 33)
      ..add(-3 << 33);

    expect(beads.buffer.asUint8List(), [
      34,
      8,
      33,
      13,
      243,
      67,
      57,
      1,
      199,
      254,
      101,
      0,
      0,
      3,
      0,
      0,
      0,
      253,
      255,
      152,
      0,
      0,
      0,
      0,
      6,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      250,
      255,
      255,
      255
    ]);
  });

  test('conver to half and back', () {
    var h = BeadsSequence.toF16(2.5);
    var d = BeadsSequence.fromF16(h);
    expect(d, 2.5);

    h = BeadsSequence.toF16(1.1);
    d = BeadsSequence.fromF16(h);
    expect((d - 1.1).abs(), lessThanOrEqualTo(0.01));

    h = BeadsSequence.toF16(37.3);
    d = BeadsSequence.fromF16(h);
    expect((d - 37.3).abs(), lessThanOrEqualTo(0.02));

    h = BeadsSequence.toF16(-37.3);
    d = BeadsSequence.fromF16(h);
    expect((d - -37.3).abs(), lessThanOrEqualTo(0.02));

    h = BeadsSequence.toF16(4958737.3);
    d = BeadsSequence.fromF16(h);
    expect((d - 4958737.3).abs(), greaterThan(20));
  });

  test('conver Nan inf and -inf to half and back', () {
    expect(BeadsSequence.fromF16(BeadsSequence.toF16(double.nan)).isNaN, true);
    expect(
        BeadsSequence.fromF16(BeadsSequence.toF16(double.infinity)).isInfinite,
        true);
    expect(
        BeadsSequence.fromF16(BeadsSequence.toF16(double.infinity)).isNegative,
        false);
    expect(
        BeadsSequence.fromF16(BeadsSequence.toF16(double.negativeInfinity))
            .isInfinite,
        true);
    expect(
        BeadsSequence.fromF16(BeadsSequence.toF16(double.negativeInfinity))
            .isNegative,
        true);
  });

  test('add nan inf -inf', () {
    final beads = BeadsSequence()
      ..add(double.nan)
      ..add(double.infinity)
      ..add(double.negativeInfinity);
    expect(beads.buffer.asUint8List(), [8, 3, 187, 1, 124, 0, 124, 11, 0, 252]);
  });

  test('add number which are repsenentable as f16', () {
    final beads = BeadsSequence()
      ..add(0.5, tolerance: 0.001)
      ..add(0.25, tolerance: 0.001)
      ..add(1.5, tolerance: 0.001);
    expect(beads.buffer.asUint8List(), [8, 3, 187, 0, 56, 0, 52, 11, 0, 62]);
  });

  test('add number which are repsenentable as f32', () {
    final beads = BeadsSequence()..add(0.5)..add(0.25)..add(1.5);
    expect(beads.buffer.asUint8List(),
        [14, 3, 119, 0, 0, 0, 63, 0, 0, 128, 62, 7, 0, 0, 192, 63]);
  });

  test('add number which are repsenentable as f64', () {
    final beads = BeadsSequence()..add(0.51)..add(0.251)..add(1.51);
    expect(beads.buffer.asUint8List(), [
      26,
      3,
      170,
      82,
      184,
      30,
      133,
      235,
      81,
      224,
      63,
      170,
      241,
      210,
      77,
      98,
      16,
      208,
      63,
      10,
      41,
      92,
      143,
      194,
      245,
      40,
      248,
      63
    ]);
  });

  test(
      'add number which are repsenentable as f64 with low tolerance resulting in f16',
      () {
    final beads = BeadsSequence()
      ..add(0.51, tolerance: 0.01)
      ..add(0.251, tolerance: 0.01)
      ..add(1.51, tolerance: 0.01);
    expect(beads.buffer.asUint8List(), [8, 3, 187, 20, 56, 4, 52, 11, 10, 62]);
  });

  test(
      'add number which are repsenentable as f64 with higher tolerance resulting in f32',
      () {
    final beads = BeadsSequence()
      ..add(0.51, tolerance: 0.0001)
      ..add(0.251, tolerance: 0.0001)
      ..add(1.51, tolerance: 0.0001);
    expect(beads.buffer.asUint8List(),
        [12, 3, 183, 92, 143, 2, 63, 4, 52, 7, 174, 71, 193, 63]);
  });

  test('add buffer null', () {
    final beads = BeadsSequence()..addBuffer(null);
    expect(beads.buffer.asUint8List(), [2, 1, 15, 0]);
  });

  test('add tiny utf8', () {
    final beads = BeadsSequence()..addUTF8("Max");
    expect(beads.buffer.asUint8List(), [4, 2, 60, 77, 97, 120]);
  });

  test('add tiny utf16', () {
    final beads = BeadsSequence()..addUTF16("Max");
    expect(beads.buffer.asUint8List(), [7, 2, 108, 77, 0, 97, 0, 120, 0]);
  });

  test('add i16 to big endian beads', () {
    final beads = BeadsSequence(endian: Endian.big)..add(313);
    expect(beads.buffer.asUint8List(), [1, 3, 3, 1, 57]);
  });

  test('create beads from another beads in little endian', () {
    final beads1 = BeadsSequence()..add(313);

    final beads2 = BeadsSequence.from(beads1.buffer)..add(256);

    final beads3 = BeadsSequence.from(beads2.buffer)..add(13);

    expect(beads1.buffer.asUint8List(), [3, 1, 3, 57, 1]);
    expect(beads2.buffer.asUint8List(), [6, 3, 3, 57, 1, 3, 0, 1]);
    expect(beads3.buffer.asUint8List(), [8, 5, 3, 57, 1, 3, 0, 1, 1, 13]);
  });

  test('create beads from another beads in big endian', () {
    final beads1 = BeadsSequence(endian: Endian.big)..add(313);

    final beads2 = BeadsSequence.from(beads1.buffer)..add(256);

    final beads3 = BeadsSequence.from(beads2.buffer)..add(13);

    expect(beads1.buffer.asUint8List(), [1, 3, 3, 1, 57]);
    expect(beads2.buffer.asUint8List(), [3, 6, 3, 1, 57, 3, 1, 0]);
    expect(beads3.buffer.asUint8List(), [5, 8, 3, 1, 57, 3, 1, 0, 1, 13]);
  });

  test(
      'create beads from another beads and change initial bead without changing the second one',
      () {
    final beads1 = BeadsSequence()..add(313);

    final beads2 = BeadsSequence.from(beads1.buffer)..add(256);

    expect(beads1.buffer.asUint8List(), [3, 1, 3, 57, 1]);
    expect(beads2.buffer.asUint8List(), [6, 3, 3, 57, 1, 3, 0, 1]);

    beads1.add(45);
    expect(beads1.buffer.asUint8List(), [4, 2, 19, 57, 1, 45]);
    expect(beads2.buffer.asUint8List(), [6, 3, 3, 57, 1, 3, 0, 1]);
  });

  test('create a bead of numbers and iterate over it', () {
    final beads = BeadsSequence();
    const array = [
      13,
      456456,
      5.8,
      2.5,
      -234234,
      double.infinity,
      null,
      -3,
      0,
      29342049823423,
      -0.1
    ];
    for (var item in array) {
      beads.add(item);
    }
    var newArray = [];
    for (var value in beads) {
      newArray.add(value.number);
    }
    expect(newArray, array);
  });

  test(
      'create beads from f16 compatible numbers with tolerance and iterate over them',
      () {
    final beads = BeadsSequence();
    // sadly double.nan values are not comparable to each other
    const array = [
      2.5,
      double.infinity,
      null,
      0,
      7,
      -7,
      double.negativeInfinity,
      -1.5
    ];
    for (var item in array) {
      beads.add(item, tolerance: 0.01);
    }
    var newArray = [];
    for (var value in beads) {
      newArray.add(value.number);
    }
    expect(newArray, array);
  });

  test('add utf8 strings and iterate over them', () {
    final beads = BeadsSequence();
    const array = [
      'Max',
      'Maxim',
      'Alex',
      'Leo',
      'Very Long string which is bigger than 16 characters'
    ];
    for (var item in array) {
      beads.addUTF8(item);
    }
    var newArray = [];
    for (var value in beads) {
      newArray.add(value.utf8String);
    }
    expect(newArray, array);
  });

  test('add utf16 strings and iterate over them', () {
    final beads = BeadsSequence();
    const array = [
      'Max',
      'Maxim',
      'Alex',
      'Leo',
      'Very Long string which is bigger than 16 characters'
    ];
    for (var item in array) {
      beads.addUTF16(item);
    }
    var newArray = [];
    for (var value in beads) {
      newArray.add(value.utf16String);
    }
    expect(newArray, array);
  });

  test('add utf16 strings compacted and iterate over them', () {
    final beads = BeadsSequence();
    const array = [
      'Max',
      'Maxim',
      'Alex',
      'Leo',
      'Very Long string which is bigger than 16 characters'
    ];
    for (var item in array) {
      beads.addUTF16(item, compacted: true);
    }
    var newArray = [];
    for (var value in beads) {
      newArray.add(value.utf16String);
    }
    expect(newArray, array);
  });

  test('add utf16 strings in big endian and iterate over them', () {
    final beads = BeadsSequence(endian: Endian.big);
    const array = ['Maxim Zaks', 'Max'];
    for (var item in array) {
      beads.addUTF16(item);
    }
    var newArray = [];
    for (var value in beads) {
      newArray.add(value.utf16String);
    }
    expect(newArray, array);
  });

  test('create two beads and append them', () {
    final beads1 = BeadsSequence()..add(1)..add(2)..add(3);
    final beads2 = BeadsSequence()
      ..add(4)
      ..add(5)
      ..add(null)
      ..addUTF16('Max')
      ..addUTF16('Maxim Zaks')
      ..addUTF16('And the others', compacted: true);

    beads1.append(beads2);
    beads1.add(45);

    var array = [];
    for (var value in beads1) {
      if (value.isNumber) {
        array.add(value.number);
      } else {
        array.add(value.utf16String);
      }
    }
    expect(array,
        [1, 2, 3, 4, 5, null, 'Max', 'Maxim Zaks', 'And the others', 45]);
  });

  test(
      'create two beads and append them, first bead has even amount of elements',
      () {
    final beads1 = BeadsSequence()..add(1)..add(2)..add(3)..add(3.5);
    final beads2 = BeadsSequence()
      ..add(4)
      ..add(5)
      ..add(null)
      ..addUTF16('Max')
      ..addUTF16('Maxim Zaks')
      ..addUTF16('And the others', compacted: true);

    beads1.append(beads2);
    beads1.add(45);

    var array = [];
    for (var value in beads1) {
      if (value.isNumber) {
        array.add(value.number);
      } else {
        array.add(value.utf16String);
      }
    }
    expect(array,
        [1, 2, 3, 3.5, 4, 5, null, 'Max', 'Maxim Zaks', 'And the others', 45]);
  });

  test(
      'create two beads and append them, first bead has even amount of elements second bead has odd amount of elements',
      () {
    final beads1 = BeadsSequence()..add(1)..add(2)..add(3)..add(3.5);
    final beads2 = BeadsSequence()
      ..add(4)
      ..add(5)
      ..add(null)
      ..addUTF16('Max')
      ..addUTF16('Maxim Zaks')
      ..addUTF16('And the others', compacted: true)
      ..add(0.1);

    beads1.append(beads2);
    beads1.add(45);

    var array = [];
    for (var value in beads1) {
      if (value.isNumber) {
        array.add(value.number);
      } else {
        array.add(value.utf16String);
      }
    }
    expect(array, [
      1,
      2,
      3,
      3.5,
      4,
      5,
      null,
      'Max',
      'Maxim Zaks',
      'And the others',
      0.1,
      45
    ]);
  });

  test(
      'create two beads with different endianness and append them will cause an exception',
      () {
    final beads1 = BeadsSequence(endian: Endian.little)..add(1)..add(2)..add(3);
    final beads2 = BeadsSequence(endian: Endian.big)
      ..add(4)
      ..add(5)
      ..addUTF16('Max')
      ..addUTF16('Maxim Zaks')
      ..addUTF16('And the others', compacted: true);

    var exceptionCatched = false;
    try {
      beads1.append(beads2);
    } catch (e) {
      exceptionCatched = true;
    }

    expect(exceptionCatched, true);
  });

  test('Add two compacted utf16 string after another', () {
    final beads = BeadsSequence()
      ..addUTF16('Maxim Zaks', compacted: true)
      ..addUTF16('Some other people', compacted: true)
      ..addUTF16('3')
      ..addUTF16('-456');
    var array = [];
    for (var value in beads) {
      array.add(value.utf16String);
    }
    expect(array, ['Maxim Zaks', 'Some other people', '3', '-456']);
  });

  test('append buffer lower than 16 bytes, higher than 16 bytes and comapcted',
      () {
    final data1 = Uint8List.fromList(
        [0, 1, 34, 67, 0, 0, 0, 0, 45, 98, 123, 201, 0, 0, 0]);
    final beads1 = BeadsSequence()..addBuffer(data1.buffer);
    expect(beads1.buffer.lengthInBytes, 18);

    final data2 = Uint8List.fromList(
        [0, 1, 34, 67, 0, 0, 0, 0, 45, 98, 123, 201, 0, 0, 0]);
    final beads2 = BeadsSequence()..addBuffer(data2.buffer, compacted: true);
    // tiny buffers are not compacted
    expect(beads2.buffer.lengthInBytes, 18);

    final data3 = Uint8List.fromList(
        [0, 1, 34, 67, 0, 0, 0, 0, 45, 98, 123, 201, 0, 0, 0, 13]);
    final beads3 = BeadsSequence()..addBuffer(data3.buffer);
    expect(beads3.buffer.lengthInBytes, 20);

    final data4 = Uint8List.fromList(
        [0, 1, 34, 67, 0, 0, 0, 0, 45, 98, 123, 201, 0, 0, 0, 13]);
    final beads4 = BeadsSequence()..addBuffer(data4.buffer, compacted: true);
    // compaction reduces the size by 25%
    expect(beads4.buffer.lengthInBytes, 15);
  });

  test('Create little endian bead with 1000 elements', () {
    final beads = BeadsSequence(endian: Endian.little);
    for (var i = 0; i < 1000; i++) {
      beads.add(i);
    }
    expect(beads.buffer.lengthInBytes, 2248);
    var index = 0;
    for (var bead in beads) {
      expect(bead.number, index);
      index++;
    }
  });

  test('Create big endian bead with 1000 elements', () {
    final beads = BeadsSequence(endian: Endian.big);
    for (var i = 0; i < 1000; i++) {
      beads.add(i);
    }
    expect(beads.buffer.lengthInBytes, 2248);
    var index = 0;
    for (var bead in beads) {
      expect(bead.number, index);
      index++;
    }
  });

  test('Create little endian bead with 100_000 elements', () {
    final beads = BeadsSequence(endian: Endian.little);
    for (var i = 0; i < 100000; i++) {
      beads.add(i);
    }
    expect(beads.buffer.lengthInBytes, 318680);
    var index = 0;
    for (var bead in beads) {
      expect(bead.number, index);
      index++;
    }
  });

  test('Create big endian bead with 100_000 elements', () {
    final beads = BeadsSequence(endian: Endian.big);
    for (var i = 0; i < 100000; i++) {
      beads.add(i);
    }
    expect(beads.buffer.lengthInBytes, 318680);
    var index = 0;
    for (var bead in beads) {
      expect(bead.number, index);
      index++;
    }
  });

  test('Debug representation littel endian', () {
    final beads = BeadsSequence(endian: Endian.little);
    for (var i = 0; i < 5; i++) {
      beads.add(i);
    }
    beads.addUTF8("Max");
    beads.add(null);
    expect(beads.debugRepresentation,
        "[12|8][1](0)[1](1)[1](2)[1](3)[1](4)[12][3][77, 97, 120][15]");
  });

  test('Debug representation big endian', () {
    final beads = BeadsSequence(endian: Endian.big);
    for (var i = 0; i < 5; i++) {
      beads.add(i);
    }
    beads.addUTF8("Max");
    beads.add(null);
    expect(beads.debugRepresentation,
        "[8|12][1](0)[1](1)[1](2)[1](3)[1](4)[12][3][77, 97, 120][15]");
  });

  test('add 1000 byte buffer compacted', () {
    final beads = BeadsSequence();
    beads.addBuffer(Uint8List(1000).buffer, compacted: true);
    beads.addBuffer(Uint8List(1000).buffer, compacted: true);
    expect(beads.buffer.lengthInBytes, 264);
    var beadsCount = 0;
    for (var bead in beads) {
      expect(bead.isCompactData, true);
      expect(bead.data.lengthInBytes, 1000);
      beadsCount++;
    }
    expect(beadsCount, 2);
  });

  test('add 100_000 byte buffer compacted', () {
    final beads = BeadsSequence();
    beads.addBuffer(Uint8List(100000).buffer, compacted: true);
    beads.addBuffer(Uint8List(100000).buffer, compacted: true);
    expect(beads.buffer.lengthInBytes, 25022);
    var beadsCount = 0;
    for (var bead in beads) {
      expect(bead.isCompactData, true);
      expect(bead.data.lengthInBytes, 100000);
      beadsCount++;
    }
    expect(beadsCount, 2);
  });

  test('Stream tiny beads sequence little endian', () async {
    final beads = BeadsSequence(endian: Endian.little)
      ..add(1)
      ..add(null)
      ..addUTF8('Max');
    var buffer = [];
    await for (var b in beads.bufferStream()) {
      buffer.addAll(b.asUint8List());
    }
    expect(buffer, [6, 4, 241, 1, 60, 77, 97, 120]);
    expect(beads.buffer.asUint8List(), buffer);
  });

  test('Stream tiny beads sequence big endian', () async {
    final beads = BeadsSequence(endian: Endian.big)
      ..add(1)
      ..add(null)
      ..addUTF8('Max');
    var buffer = [];
    await for (var b in beads.bufferStream()) {
      buffer.addAll(b.asUint8List());
    }
    expect(buffer, [4, 6, 241, 1, 60, 77, 97, 120]);
    expect(beads.buffer.asUint8List(), buffer);
  });

  test('Stream small beads sequence little endian', () async {
    final beads = BeadsSequence(endian: Endian.little);
    for (var i = 0; i < 300; i++) {
      beads.add(i);
    }
    var buffer = [];
    await for (var b in beads.bufferStream()) {
      buffer.addAll(b.asUint8List());
    }
    expect(beads.buffer.asUint8List(), buffer);
  });

  test('Stream small beads sequence big endian', () async {
    final beads = BeadsSequence(endian: Endian.big);
    for (var i = 0; i < 300; i++) {
      beads.add(i);
    }
    var buffer = [];
    await for (var b in beads.bufferStream()) {
      buffer.addAll(b.asUint8List());
    }
    expect(beads.buffer.asUint8List(), buffer);
  });

  test('Stream big beads sequence little endian', () async {
    final beads = BeadsSequence(endian: Endian.little);
    for (var i = 0; i < 100000; i++) {
      beads.add(i);
    }
    var buffer = [];
    await for (var b in beads.bufferStream()) {
      buffer.addAll(b.asUint8List());
    }
    expect(beads.buffer.asUint8List(), buffer);
  });

  test('Stream big beads sequence big endian', () async {
    final beads = BeadsSequence(endian: Endian.big);
    for (var i = 0; i < 100000; i++) {
      beads.add(i);
    }
    var buffer = [];
    await for (var b in beads.bufferStream()) {
      buffer.addAll(b.asUint8List());
    }
    expect(beads.buffer.asUint8List(), buffer);
  });
}
