import 'dart:async' show Stream;
import 'dart:collection' show IterableMixin;
import 'dart:typed_data'
    show ByteData, Endian, ByteBuffer, Uint8List, Uint16List;
import 'dart:convert' show utf8;

import 'dart:math' show max, min;

import 'package:meta/meta.dart' show required;

enum _BeadType {
  skip, // 0
  u8, // 1
  i8, // 2
  u16, // 3
  i16, // 4
  u32, // 5
  i32, // 6
  f32, // 7
  u64, // 8
  i64, // 9
  f64, // 10
  f16, // 11
  tinyData, // 12
  compactData, // 13
  data, // 14
  nil // 15
}

const _max_u8 = ((1 << 8) - 1);
const _max_u16 = ((1 << 16) - 1);
const _max_u32 = ((1 << 32) - 1);

const _max_u7 = ((1 << 7) - 1);
const _max_u15 = ((1 << 15) - 1);
const _max_u31 = ((1 << 31) - 1);

const _min_u8 = (-(1 << 7));
const _min_u16 = (-(1 << 15));
const _min_u32 = (-(1 << 31));

/// Beads is an append only data structure optimised for memory footprint.
/// It is a simple solution for data serialisation, incorporating byte packing techniques.
/// In order to extract values from beads, users need to iterate over it.
class BeadsSequence with IterableMixin<BeadValue> {
  ByteData _buffer;
  int _elementCount = 0;
  int _flagIndex = 0;
  int _cursor = 0;
  Endian _endian = Endian.host;

  /// Creates a new instance backed by an empty [ByteData] instance.
  /// The initial length of the [ByteData] instance can be set through length parameter.
  /// If provided length parameter is smaller than 8 it will be set to 8.
  /// The values in beads can be stored based on provided [Endian] parameter.
  /// If [Endian] parameter is not provided, [Endian.host] is taken.
  BeadsSequence({int length = 64, Endian endian}) {
    _buffer = ByteData(length > 0 ? length : 8);
    if (endian != null) {
      _endian = endian;
    }
  }

  /// Creates a new instance backed by provided [ByteBuffer] instance,
  /// which need to contain a valid beads buffer.
  /// If provided [ByteBuffer] instance is not valid, an exception is thrown.
  /// This constructor is used for beads de-serialisation.
  /// However as it creates a [BeadsSequence] instance users can also continue append new values to it.
  /// The endianness is defined by original beads sequence.
  BeadsSequence.from(ByteBuffer value) {
    final length = value.lengthInBytes;
    final valueList = value.asUint8List();
    if (length <= 2) {
      throw "Invalid byte buffer, length must be bigger than 2";
    }
    if (length - 2 <= _max_u7) {
      final header1 = valueList[0];
      final header2 = valueList[1];
      if (header1 == length - 2) {
        _endian = Endian.little;
        _cursor = header1;
        _elementCount = header2;
      } else if (header2 == length - 2) {
        _endian = Endian.big;
        _cursor = header2;
        _elementCount = header1;
      } else {
        throw "Invalid byte buffer, the header does not match the beads size";
      }
      if (_elementCount.isOdd) {
        _elementCount++;
      }
      _buffer = ByteData.view(value, 2);
    }
  }

  /// Adds a number to the sequence in the most compact way possible.
  /// Null values are stored only as a 4 bit flag.
  /// Integer numbers from -2^7 .. 0 .. 2^8-1 are stored in 1 byte.
  /// Integer numbers between -2^15 .. -2^7-1 and 2^8 .. 2^16-1 are stored in 2 byte.
  /// Integer numbers between -2^31 .. -2^15-1 and 2^16 .. 2^32-1 are stored in 4 byte.
  /// Integer numbers between -2^63 .. -2^31-1 and 2^32 .. 2^64-1 are stored in 8 byte.
  /// [double.infinity], [double.nan] and [double.negativeInfinity] are stored in 2 bytes.
  /// Floating point numbers are down casted from double precision (8 bytes) to single precision (4 bytes) and stored as such, if the difference is tolerable.
  /// By providing the optional tolerance parameter, user can influence the tolerance check.
  /// Default tolerance is set to 0.0 - meaning that the values has to be exactly the same, but can be adjusted up to 0.1 - meaning that 0.1 and (0.09 or 0.11) are close enough to each other, to be stored in a lesser precision.
  /// If tolerance is set higher than 0.0, the floating point number is also checked against half precision (2 bytes) representation.
  /// As mentioned before 0 value is stored as 1 byte.
  /// If absolute value of provided number is lower than tolerance value, it will be stored as 0 in 1 byte.
  add(num number, {double tolerance = 0.0}) {
    assert(tolerance >= 0.0 && tolerance <= 0.1,
        "please set tolerance as a number between 0.0 and 0.1");
    if (_addNull(number)) {
      return;
    }
    if (number.abs() <= tolerance) {
      _addU8(0);
      return;
    }
    if (number.isInfinite || number.isNaN) {
      _addF16(number);
      return;
    }
    var intNumber = number.toInt();
    if ((intNumber - number).abs() <= tolerance) {
      if (intNumber.isNegative) {
        if (intNumber >= _min_u8) {
          _addI8(intNumber);
        } else if (intNumber >= _min_u16) {
          _addI16(intNumber);
        } else if (intNumber >= _min_u32) {
          _addI32(intNumber);
        } else {
          _addI64(intNumber);
        }
      } else {
        if (intNumber <= _max_u8) {
          _addU8(intNumber);
        } else if (intNumber <= _max_u16) {
          _addU16(intNumber);
        } else if (intNumber <= _max_u32) {
          _addU32(intNumber);
        } else {
          _addU64(intNumber);
        }
      }
    } else {
      var doubleNumber = number.toDouble();
      if (tolerance > 0.0) {
        final f16 = toF16(doubleNumber);
        if ((doubleNumber - fromF16(f16)).abs() < tolerance) {
          _addAsF16AlreadyConvertedValue(f16);
          return;
        }
      }
      if ((doubleNumber - toF32(doubleNumber.toDouble())).abs() <= tolerance) {
        _addF32(doubleNumber);
      } else {
        _addF64(doubleNumber);
      }
    }
  }

  /// Adds a string value to the sequence encoded in UTF8 format.
  /// UTF8 is a very good choice for byte density, specifically when it comes to numbers and latin alphabet.
  /// Dart [String] is however stored internally in UTF16 format, meaning that it undergoes a conversion step, which might result in a performance hit.
  addUTF8(String value) {
    if (_addNull(value)) {
      return;
    }
    addBuffer(Uint8List.fromList(utf8.encode(value)).buffer);
  }

  /// Adds a string value to the sequence encoded in UTF16 format.
  /// The endianness set for the whole beads sequence is checked against [Endian.host] value and [String.codeUnits] are transformed if necessary.
  /// The resulting buffer can also be compacted. Please have a look at [addBuffer] method signature to get more information on that topic.
  addUTF16(String value, {bool compacted = false}) {
    if (_addNull(value)) {
      return;
    }
    if (Endian.host == _endian) {
      addBuffer(Uint16List.fromList(value.codeUnits).buffer,
          compacted: compacted);
    } else {
      // need to rotate numbers to represent proper endianness
      final buffer = Uint16List.fromList(value.codeUnits).buffer.asByteData();
      for (var i = 0; i < buffer.lengthInBytes;) {
        final b1 = buffer.getUint8(i);
        final b2 = buffer.getUint8(i + 1);
        buffer.setUint8(i, b2);
        buffer.setUint8(i + 1, b1);
        i += 2;
      }
      addBuffer(buffer.buffer, compacted: compacted);
    }
  }

  /// Adds a byte buffer to the sequence.
  /// If [ByteBuffer.lengthInBytes] is smaller or equal 16,
  /// than buffer is always stored as [_BeadType.tinyData] which stores the size of the buffer as 4 bit flag.
  /// Otherwise it depends if user set compacted parameter to true.
  /// If compacted is not set to true, the buffer is prefixed with its lengthInBytes value and stored as is.
  /// Otherwise the buffer is iterated over in 8 byte chunks.
  /// Every chunk is prefixed with a bit mask, which identifies if byte x is bigger than 0.
  /// Only bytes, which are bigger than 0 are stored.
  /// This implies that in best case scenario (byte buffer consisted of only 0 bytes) we can reduce the size to 1/8 -> 12.5%
  /// And in worst case scenario we increase the size of the buffer by 1/8th, resulting in 112.5% of the size.
  /// The average case should be some where below 100%.
  addBuffer(ByteBuffer value, {bool compacted = false}) {
    if (_addNull(value)) {
      return;
    }
    var lengthInBytes = value.lengthInBytes;
    if (lengthInBytes < 16) {
      _prepareToAppend(lengthInBytes + 1);
      _addTag(_BeadType.tinyData);
      _addLengthAsTag(lengthInBytes);
      _copy(
          from: ByteData.view(value),
          to: _buffer,
          offset: _cursor,
          length: lengthInBytes);
      _cursor += lengthInBytes;
      return;
    }
    if (compacted) {
      final valueAsList = value.asUint8List();
      var compactDataLength = 0;
      var compactData = ByteData((lengthInBytes * 1.125).ceil());
      var flagCursor = 0;
      for (var i = 0; i < lengthInBytes; i++) {
        if (i % 8 == 0) {
          flagCursor = compactDataLength;
          compactDataLength++;
        }
        var byte = valueAsList[i];

        if (byte != 0) {
          final bitmask = 1 << (i % 8);
          compactData.setUint8(
              flagCursor, compactData.getUint8(flagCursor) | bitmask);
          compactData.setUint8(compactDataLength, byte);
          compactDataLength++;
        }
      }
      _prepareToAppend(1);
      _addTag(_BeadType.compactData);
      final maxValue = max(lengthInBytes, compactDataLength);
      if (maxValue <= _max_u8) {
        _addU8(compactDataLength);
        _prepareToAppend(1);
        _buffer.setUint8(_cursor, lengthInBytes);
        _cursor += 1;
      } else if (maxValue <= _max_u16) {
        _addU16(compactDataLength);
        _prepareToAppend(2);
        _buffer.setUint16(_cursor, lengthInBytes, _endian);
        _cursor += 2;
      } else if (maxValue <= _max_u32) {
        _addU32(compactDataLength);
        _prepareToAppend(4);
        _buffer.setUint32(_cursor, lengthInBytes, _endian);
        _cursor += 4;
      } else {
        _addU64(compactDataLength);
        _prepareToAppend(8);
        _buffer.setUint32(_cursor, lengthInBytes, _endian);
        _cursor += 8;
      }
      _prepareToAppend(compactDataLength);
      _copy(
          from: compactData,
          to: _buffer,
          offset: _cursor,
          length: compactDataLength);
      _cursor += compactDataLength;
    } else {
      _prepareToAppend(1);
      _addTag(_BeadType.data);
      add(lengthInBytes);
      _prepareToAppend(lengthInBytes);
      _copy(
          from: ByteData.view(value),
          to: _buffer,
          offset: _cursor,
          length: lengthInBytes);
      _cursor += lengthInBytes;
    }
  }

  /// Appends a provided [BeadsSequence] to this [BeadsSequence].
  /// This operation can be performed quite efficiently.
  /// However it is only allowed for beads of equal endianness.
  /// We might need to grow [ByteData] of this beads sequence.
  /// And than directly append [ByteData] of provided beads sequence.
  /// No decoding of the values is needed.
  void append(BeadsSequence beads) {
    if (_endian != beads._endian) {
      throw "You can only append beads which have same endianness, please consider to add bead after bead";
    }
    if (_elementCount.isOdd) {
      // use bead tag so that you don't need to increase later again
      _elementCount++;
    }
    _prepareToAppend(beads._cursor);
    _copy(
        from: beads._buffer,
        to: _buffer,
        offset: _cursor,
        length: beads._cursor);
    _elementCount += beads._elementCount;
    _cursor += beads._cursor;
    if (_elementCount.isOdd) {
      _elementCount++;
    }
  }

  bool _addNull(value) {
    if (value == null) {
      _prepareToAppend(1);
      _addTag(_BeadType.nil);
      return true;
    }
    return false;
  }

  /// This getter is used for serialisation of the beads sequence.
  /// It returns a new buffer which contains beads prepended with a header.
  /// Header contains of two numbers:
  /// - Buffer length without the header (beads length)
  /// - Number of elements stored in beads
  ///
  /// The arrangement of the numbers is endianness dependent (https://en.wikipedia.org/wiki/Endianness).
  /// If beads are stored in little endian, beads length comes first, followed by number of elements.
  /// If beads are stored in big endian, it is the other way around.
  /// This way the reader can identify the endianness by following this steps:
  /// 1. Get the byte length of the buffer
  /// 2. Compute the length of the header by checking if:
  ///   - byteLength <= max_u7 + 2, than header is 2 bytes long
  ///   - byteLength <= max_u15 + 4, than header is 4 bytes long
  ///   - byteLength <= max_u31 + 8, than header is 8 bytes long
  ///   - other wise it is 16 bytes long
  /// 3. Check if buffer length minus header length is equal to frist or second header value.
  ///
  /// Note: The beads length and number of elements needs to be stored in the same amount of bytes.
  /// In worst case scenario number of elements can be twice as big as beads length (e.g. if every element is a null or a skip)
  /// This is why we check byteLength against max_u7, max_u15 and max_u31
  ByteBuffer get buffer {
    // This is needed because otherwise the reader would not be able to identify the endianness.
    final bufferSize = _cursor == _elementCount ? _cursor + 1 : _cursor;

    if (bufferSize <= _max_u7) {
      final bufferCopy = ByteData(bufferSize + 2);
      if (_endian == Endian.little) {
        bufferCopy.setUint8(0, bufferSize);
        bufferCopy.setUint8(1, _elementCount);
      } else {
        bufferCopy.setUint8(0, _elementCount);
        bufferCopy.setUint8(1, bufferSize);
      }
      _copy(from: _buffer, to: bufferCopy, offset: 2, length: _cursor);
      return bufferCopy.buffer;
    } else if (bufferSize <= _max_u15) {
      final bufferCopy = ByteData(bufferSize + 4);
      if (_endian == Endian.little) {
        bufferCopy.setUint16(0, bufferSize, _endian);
        bufferCopy.setUint16(2, _elementCount, _endian);
      } else {
        bufferCopy.setUint16(0, _elementCount, _endian);
        bufferCopy.setUint16(2, bufferSize, _endian);
      }
      _copy(from: _buffer, to: bufferCopy, offset: 4, length: _cursor);
      return bufferCopy.buffer;
    } else if (bufferSize <= _max_u31) {
      final bufferCopy = ByteData(bufferSize + 8);
      if (_endian == Endian.little) {
        bufferCopy.setUint32(0, bufferSize, _endian);
        bufferCopy.setUint32(4, _elementCount, _endian);
      } else {
        bufferCopy.setUint32(0, _elementCount, _endian);
        bufferCopy.setUint32(4, bufferSize, _endian);
      }
      _copy(from: _buffer, to: bufferCopy, offset: 8, length: _cursor);
      return bufferCopy.buffer;
    } else {
      final bufferCopy = ByteData(bufferSize + 16);
      if (_endian == Endian.little) {
        bufferCopy.setUint64(0, bufferSize, _endian);
        bufferCopy.setUint64(8, _elementCount, _endian);
      } else {
        bufferCopy.setUint64(0, _elementCount, _endian);
        bufferCopy.setUint64(8, bufferSize, _endian);
      }
      _copy(from: _buffer, to: bufferCopy, offset: 16, length: _cursor);
      return bufferCopy.buffer;
    }
  }

  /// This function is similar to [buffer] getter with a difference that it returns a [Stream].
  /// Use this function, if you don't want to create a big [ByteBuffer] upfront, but rather want to stream it in smaller chunks asynchronously.
  /// The first item in the stream will be the header (for more details please read [buffer] getter documentation)
  /// Further items in the stream will be the actual beads buffer breaken down into chunks smaller or as big as defined in [chunkSize] parameter.
  Stream<ByteBuffer> bufferStream([int chunkSize = 64]) async* {
    final bufferSize = _cursor == _elementCount ? _cursor + 1 : _cursor;
    final elementCount = _elementCount;
    if (bufferSize <= _max_u7) {
      final header = ByteData(2);
      if (_endian == Endian.little) {
        header.setUint8(0, bufferSize);
        header.setUint8(1, elementCount);
      } else {
        header.setUint8(0, elementCount);
        header.setUint8(1, bufferSize);
      }
      yield header.buffer;
    } else if (bufferSize <= _max_u15) {
      final header = ByteData(4);
      if (_endian == Endian.little) {
        header.setUint16(0, bufferSize, _endian);
        header.setUint16(2, elementCount, _endian);
      } else {
        header.setUint16(0, elementCount, _endian);
        header.setUint16(2, bufferSize, _endian);
      }
      yield header.buffer;
    } else if (bufferSize <= _max_u31) {
      final header = ByteData(8);
      if (_endian == Endian.little) {
        header.setUint32(0, bufferSize, _endian);
        header.setUint32(4, elementCount, _endian);
      } else {
        header.setUint32(0, elementCount, _endian);
        header.setUint32(4, bufferSize, _endian);
      }
      yield header.buffer;
    } else {
      final header = ByteData(16);
      if (_endian == Endian.little) {
        header.setUint64(0, bufferSize, _endian);
        header.setUint64(8, elementCount, _endian);
      } else {
        header.setUint64(0, elementCount, _endian);
        header.setUint64(8, bufferSize, _endian);
      }
      yield header.buffer;
    }
    for (var i = 0; i < bufferSize; i += chunkSize) {
      final currentChunkSize = min(chunkSize, bufferSize - i);
      final chunk = ByteData(currentChunkSize);
      _copy(from: _buffer, to: chunk, offsetFrom: i, length: currentChunkSize);
      yield chunk.buffer;
    }
  }

  /// Returns a string which can be used for debug purposes.
  /// It reflects the internal structure of the sequence in a more human readable way.
  /// First two numbers inside of a `[]` represent the Beads sequence header dependent on endianness.
  /// Bead values are represented by `[tagId](numeric value)`, or `[tagId][data length][comma separated u8 values]`.
  /// A null value is represented only by `[15]` which is the number of the null tag.
  /// Skip tags are not represented.
  String get debugRepresentation {
    final stringBuffer = StringBuffer();
    List<String> parts = [];
    if (_endian == Endian.little) {
      parts.add("[${_cursor}|${_elementCount}]");
    } else {
      parts.add("[${_elementCount}|${_cursor}]");
    }
    for (var element in this) {
      parts.add("[${element._beadType.index}]");
      if (element.isData) {
        parts.add("[${element._dataLength}]");
        parts.add("${element.data.asUint8List()}");
      } else if (element.isNil == false) {
        parts.add("(${element.number})");
      }
    }
    stringBuffer.writeAll(parts);
    return stringBuffer.toString();
  }

  _addTag(_BeadType type) {
    if (_elementCount.isEven) {
      _flagIndex = _cursor;
      _buffer.setUint8(_flagIndex, type.index);
      _cursor++;
    } else {
      final prevFlag = _buffer.getUint8(_flagIndex);
      _buffer.setUint8(_flagIndex, prevFlag | (type.index << 4));
    }
    _elementCount++;
  }

  _addLengthAsTag(int length) {
    assert(length < 16);
    if (_elementCount.isEven) {
      _flagIndex = _cursor;
      _buffer.setUint8(_flagIndex, length);
      _cursor++;
    } else {
      final prevFlag = _buffer.getUint8(_flagIndex);
      _buffer.setUint8(_flagIndex, prevFlag | (length << 4));
    }
    _elementCount++;
  }

  _addU8(int number) {
    _prepareToAppend(2);
    _addTag(_BeadType.u8);
    _buffer.setUint8(_cursor, number);
    _cursor += 1;
  }

  _addU16(int number) {
    _prepareToAppend(3);
    _addTag(_BeadType.u16);
    _buffer.setUint16(_cursor, number, _endian);
    _cursor += 2;
  }

  _addU32(int number) {
    _prepareToAppend(5);
    _addTag(_BeadType.u32);
    _buffer.setUint32(_cursor, number, _endian);
    _cursor += 4;
  }

  _addU64(int number) {
    _prepareToAppend(9);
    _addTag(_BeadType.u64);
    _buffer.setUint64(_cursor, number, _endian);
    _cursor += 8;
  }

  _addI8(int number) {
    _prepareToAppend(2);
    _addTag(_BeadType.i8);
    _buffer.setInt8(_cursor, number);
    _cursor += 1;
  }

  _addI16(int number) {
    _prepareToAppend(3);
    _addTag(_BeadType.i16);
    _buffer.setInt16(_cursor, number, _endian);
    _cursor += 2;
  }

  _addI32(int number) {
    _prepareToAppend(5);
    _addTag(_BeadType.i32);
    _buffer.setInt32(_cursor, number, _endian);
    _cursor += 4;
  }

  _addI64(int number) {
    _prepareToAppend(9);
    _addTag(_BeadType.i64);
    _buffer.setInt64(_cursor, number, _endian);
    _cursor += 8;
  }

  _addF16(double number) {
    _prepareToAppend(3);
    _addTag(_BeadType.f16);
    _buffer.setUint16(_cursor, toF16(number), _endian);
    _cursor += 2;
  }

  _addAsF16AlreadyConvertedValue(int number) {
    _prepareToAppend(3);
    _addTag(_BeadType.f16);
    _buffer.setUint16(_cursor, number, _endian);
    _cursor += 2;
  }

  _addF32(double number) {
    _prepareToAppend(5);
    _addTag(_BeadType.f32);
    _buffer.setFloat32(_cursor, number, _endian);
    _cursor += 4;
  }

  _addF64(double number) {
    _prepareToAppend(9);
    _addTag(_BeadType.f64);
    _buffer.setFloat64(_cursor, number, _endian);
    _cursor += 8;
  }

  _prepareToAppend(int numberOfBytes) {
    final prevLength = _buffer.lengthInBytes;
    if (_cursor + numberOfBytes < prevLength) {
      return;
    }
    var newLength = prevLength;
    while (_cursor + numberOfBytes > newLength) {
      newLength = newLength << 1;
    }
    var newBuffer = ByteData(newLength);
    _copy(from: _buffer, to: newBuffer);
    _buffer = newBuffer;
  }

  static _copy(
      {@required ByteData from,
      @required ByteData to,
      int offset = 0,
      int length,
      int offsetFrom = 0}) {
    length ??= (from.lengthInBytes - offsetFrom);
    final lengthTo = to.lengthInBytes;
    final lengthFrom = from.lengthInBytes;
    for (var i = 0; i < length;) {
      final posTo = i + offset;
      final posFrom = i + offsetFrom;

      if (posTo + 8 < lengthTo && posTo + 8 < lengthFrom) {
        to.setUint64(posTo, from.getUint64(posFrom));
        i += 8;
      } else if (posTo + 4 < lengthTo && posTo + 4 < lengthFrom) {
        to.setUint32(posTo, from.getUint32(posFrom));
        i += 4;
      } else if (posTo + 2 < lengthTo && posTo + 2 < lengthFrom) {
        to.setUint16(posTo, from.getUint16(posFrom));
        i += 2;
      } else {
        to.setUint8(posTo, from.getUint8(posFrom));
        i++;
      }
    }
  }

  /// Convert a [double] value to a half precision (2 byte) representation.
  /// The function returns an [int] which confirms to IEEE-754 2 byte representation of floating-point number.
  /// Meant to be used together with [BeadsSequence.fromF16] function.
  static int toF16(double value) {
    if (value.isNaN) {
      return 31745;
    }
    if (value.isInfinite && value.isNegative) {
      return 64512;
    }
    if (value.isInfinite && value.isNegative == false) {
      return 31744;
    }

    var bdata = new ByteData(4);
    bdata.setFloat32(0, value);
    int f = bdata.getUint32(0);
    var sign = ((f >> 16) & 0x8000);
    var expo = ((((f & 0x7f800000) - 0x38000000) >> 13) & 0x7c00);
    var mant = ((f >> 13) & 0x03ff);
    return (sign | expo | mant);
  }

  /// Convert a [int] value which bit pattern is set according to IEEE-754 2 byte representation of floating-point number, to a [double] value.
  /// Meant to be used together with [BeadsSequence.toF16] function.
  static double fromF16(int value) {
    if (value == 31745) {
      // 0b0_11111_0000000001
      return double.nan;
    }
    if (value == 64512) {
      // 0b1_11111_0000000000
      return double.negativeInfinity;
    }
    if (value == 31744) {
      // 0b0_11111_0000000000
      return double.infinity;
    }

    var sign = ((value & 0x8000) << 16);
    var expo = (((value & 0x7c00) + 0x1C000) << 13);
    var mant = ((value & 0x03FF) << 13);
    var f = (sign | expo | mant);

    var bdata = new ByteData(4);
    bdata.setInt32(0, f);
    return bdata.getFloat32(0);
  }

  // Returns a single precision floating-point number.
  static double toF32(double value) {
    var bdata = new ByteData(4);
    bdata.setFloat32(0, value);
    return bdata.getFloat32(0);
  }

  @override
  Iterator<BeadValue> get iterator =>
      _BeadsIterator(_buffer, _elementCount, _endian);
}

class _BeadsIterator implements Iterator<BeadValue> {
  final ByteData _buffer;
  final int _elementCount;
  final Endian _endian;
  var _cursor = 0;
  var _valueOffset;
  var _index = 0;
  int _typeFlag;
  _BeadType _beadType;
  int _dataLength;
  int _unpackedDataLength;

  _BeadsIterator(this._buffer, this._elementCount, this._endian);

  @override
  BeadValue get current => BeadValue._(_buffer, _valueOffset, _endian,
      _beadType, _dataLength, _unpackedDataLength);

  @override
  bool moveNext() {
    _dataLength = null;
    _unpackedDataLength = null;

    if (_index == _elementCount) {
      return false;
    }

    if (_index.isEven) {
      _typeFlag = _buffer.getUint8(_cursor);
      _cursor += 1;
      _beadType = _BeadType.values[_typeFlag & 0x0f];
    } else {
      _beadType = _BeadType.values[_typeFlag >> 4];
    }

    if (_beadType == _BeadType.skip) {
      _index++;
      return moveNext();
    }
    if (_beadType == _BeadType.nil) {
      _index++;
      return true;
    }
    if (_beadType == _BeadType.u8 || _beadType == _BeadType.i8) {
      _index++;
      _valueOffset = _cursor;
      _cursor++;
      return true;
    }
    if (_beadType == _BeadType.u16 ||
        _beadType == _BeadType.i16 ||
        _beadType == _BeadType.f16) {
      _index++;
      _valueOffset = _cursor;
      _cursor += 2;
      return true;
    }
    if (_beadType == _BeadType.u32 ||
        _beadType == _BeadType.i32 ||
        _beadType == _BeadType.f32) {
      _index++;
      _valueOffset = _cursor;
      _cursor += 4;
      return true;
    }
    if (_beadType == _BeadType.u64 ||
        _beadType == _BeadType.i64 ||
        _beadType == _BeadType.f64) {
      _index++;
      _valueOffset = _cursor;
      _cursor += 8;
      return true;
    }

    if (_beadType == _BeadType.tinyData) {
      _index++;

      if (_index.isEven) {
        _typeFlag = _buffer.getUint8(_cursor);
        _cursor += 1;
        _dataLength = _typeFlag & 0x0f;
      } else {
        _dataLength = _typeFlag >> 4;
      }
      _index++;
      _valueOffset = _cursor;
      _cursor += _dataLength;
      return true;
    }

    if (_beadType == _BeadType.data || _beadType == _BeadType.compactData) {
      _index++;

      _BeadType lengthType;
      if (_index.isEven) {
        _typeFlag = _buffer.getUint8(_cursor);
        _cursor += 1;
        lengthType = _BeadType.values[_typeFlag & 0x0f];
      } else {
        lengthType = _BeadType.values[_typeFlag >> 4];
      }
      _index++;
      if (lengthType == _BeadType.u8) {
        _dataLength = _buffer.getUint8(_cursor);
        _cursor += 1;
        if (_beadType == _BeadType.compactData) {
          _unpackedDataLength = _buffer.getUint8(_cursor);
          _cursor += 1;
        }
      } else if (lengthType == _BeadType.u16) {
        _dataLength = _buffer.getUint16(_cursor, _endian);
        _cursor += 2;
        if (_beadType == _BeadType.compactData) {
          _unpackedDataLength = _buffer.getUint16(_cursor, _endian);
          _cursor += 2;
        }
      } else if (lengthType == _BeadType.u32) {
        _dataLength = _buffer.getUint32(_cursor, _endian);
        _cursor += 4;
        if (_beadType == _BeadType.compactData) {
          _unpackedDataLength = _buffer.getUint32(_cursor, _endian);
          _cursor += 4;
        }
      } else if (lengthType == _BeadType.u64) {
        _dataLength = _buffer.getUint64(_cursor, _endian);
        _cursor += 8;
        if (_beadType == _BeadType.compactData) {
          _unpackedDataLength = _buffer.getUint64(_cursor, _endian);
          _cursor += 8;
        }
      } else {
        throw "Unexpected length type";
      }
      _valueOffset = _cursor;
      _cursor += _dataLength;
      return true;
    }

    throw "Unexpected bead type case";
  }
}

/// Representation of a single bead in beads sequence, which is used to extract the bead value.
class BeadValue {
  final ByteData _buffer;
  final int _offset;
  final Endian _endian;
  final _BeadType _beadType;
  final int _dataLength;
  final int _unpackedDataLength;

  BeadValue._(this._buffer, this._offset, this._endian, this._beadType,
      this._dataLength, this._unpackedDataLength);

  /// Use to check if the bead represents a `null` value.
  bool get isNil => _beadType == _BeadType.nil;

  /// Use to check if the bead represents an [int] value.
  bool get isInt =>
      _beadType == _BeadType.u8 ||
      _beadType == _BeadType.i8 ||
      _beadType == _BeadType.u16 ||
      _beadType == _BeadType.i16 ||
      _beadType == _BeadType.u32 ||
      _beadType == _BeadType.i32 ||
      _beadType == _BeadType.u64 ||
      _beadType == _BeadType.i64;

  /// Use to check if the bead represents an [double] value.
  bool get isDouble =>
      _beadType == _BeadType.f16 ||
      _beadType == _BeadType.f32 ||
      _beadType == _BeadType.f64;

  /// Use to check if the bead represents an [int] or a [double] value.
  bool get isNumber => isInt || isDouble;

  /// Use to check if the bead represents an [ByteBuffer] value.
  bool get isData =>
      _beadType == _BeadType.data ||
      _beadType == _BeadType.compactData ||
      _beadType == _BeadType.tinyData;

  /// Use to check if the bead was stored in a compact way, see [BeadsSequence.addBuffer] method.
  bool get isCompactData => _beadType == _BeadType.compactData;

  /// Returns an instance of [int] or `null` if underlying bead is not stored as an [int] value.
  /// In most cases you should use the [number] getter though.
  int get intValue {
    if (_beadType == _BeadType.u8) {
      return _buffer.getUint8(_offset);
    } else if (_beadType == _BeadType.i8) {
      return _buffer.getInt8(_offset);
    } else if (_beadType == _BeadType.u16) {
      return _buffer.getUint16(_offset, _endian);
    } else if (_beadType == _BeadType.i16) {
      return _buffer.getInt16(_offset, _endian);
    } else if (_beadType == _BeadType.u32) {
      return _buffer.getUint32(_offset, _endian);
    } else if (_beadType == _BeadType.i32) {
      return _buffer.getInt32(_offset, _endian);
    } else if (_beadType == _BeadType.u64) {
      return _buffer.getUint64(_offset, _endian);
    } else if (_beadType == _BeadType.i64) {
      return _buffer.getInt64(_offset, _endian);
    }
    return null;
  }

  /// Returns an instance of [double] or `null` if underlying bead is not stored as an [double] value.
  /// In most cases you should use the [number] getter though.
  double get doubleValue {
    if (_beadType == _BeadType.f16) {
      return BeadsSequence.fromF16(_buffer.getUint16(_offset, _endian));
    } else if (_beadType == _BeadType.f32) {
      return _buffer.getFloat32(_offset, _endian);
    } else if (_beadType == _BeadType.f64) {
      return _buffer.getFloat64(_offset, _endian);
    }
    return null;
  }

  /// Preferred way of extracting number value from a bead.
  /// The value can be a [num] or `null` if bead is not a number.
  num get number {
    return doubleValue ?? intValue;
  }

  /// Returns [ByteBuffer] or `null`.
  ByteBuffer get data {
    if (_beadType == _BeadType.data || _beadType == _BeadType.tinyData) {
      ByteData result = ByteData(_dataLength);
      BeadsSequence._copy(
          from: _buffer, to: result, offsetFrom: _offset, length: _dataLength);
      return result.buffer;
    } else if (_beadType == _BeadType.compactData) {
      ByteData unpackedBuffer = ByteData(_unpackedDataLength);
      var elementIndex = 0;
      var cursor = _offset;
      while (elementIndex < _unpackedDataLength &&
          cursor < (_dataLength + _offset)) {
        var tag = _buffer.getUint8(cursor);
        cursor++;
        for (var bitIndex = 0; bitIndex < 8; bitIndex++) {
          var bitMask = 1 << bitIndex;
          if (elementIndex >= _unpackedDataLength) {
            break;
          }
          if (tag & bitMask != 0) {
            unpackedBuffer.setUint8(elementIndex, _buffer.getUint8(cursor));
            cursor++;
          }
          elementIndex++;
        }
      }

      return unpackedBuffer.buffer;
    }
    return null;
  }

  /// Returns a [String] based on the [data] value converted with UTF8 decoder.
  String get utf8String {
    final data = this.data;
    if (data == null) {
      return null;
    }
    return utf8.decode(data.asUint8List());
  }

  /// Returns a [String] based on the [data] as UTF16 string according to [Endian.host].
  /// Throws an exception if the underlying data is not a multiple of 2 bytes.
  String get utf16String {
    return _utf16String(Endian.host);
  }

  String _utf16String(Endian endian) {
    final data = this.data;
    if (data == null) {
      return null;
    }
    if (data.lengthInBytes.isOdd) {
      throw "Underlying data is not a valid UTF16 buffer as it is not even.";
    }
    if (endian == _endian) {
      return String.fromCharCodes(data.asUint16List());
    } else {
      final byteData = data.asByteData();
      for (var i = 0; i < data.lengthInBytes;) {
        var byte1 = byteData.getUint8(i);
        var byte2 = byteData.getUint8(i + 1);
        byteData.setUint8(i, byte2);
        byteData.setUint8(i + 1, byte1);
        i += 2;
      }
      return String.fromCharCodes(data.asUint16List());
    }
  }
}
