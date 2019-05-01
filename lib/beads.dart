import 'dart:collection' show IterableMixin;
import 'dart:typed_data' show ByteData, Endian, ByteBuffer, Uint8List, Uint16List, Uint32List;
import 'dart:convert' show utf8;

import 'dart:math' show max;

import 'package:meta/meta.dart' show required;

enum BeadType {
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

const max_u8 = ((1 << 8) - 1);
const max_u16 = ((1 << 16) - 1);
const max_u32 = ((1 << 32) - 1);

const max_u7 = ((1 << 7) - 1);
const max_u15 = ((1 << 15) - 1);
const max_u31 = ((1 << 31) - 1);

const min_u8 = (-(1 << 7));
const min_u16 = (-(1 << 15));
const min_u32 = (-(1 << 31));

class BeadsSequence with IterableMixin<BeadValue>{
  ByteData _buffer;
  int _elementCount = 0;
  int _flagIndex = 0;
  int _cursor = 0;
  Endian _endian = Endian.host;
  BeadsSequence({int length = 64, Endian endian}) {
    _buffer = ByteData(length > 0 ? length : 8);
    if (endian != null) {
      _endian = endian;
    }
  }

  BeadsSequence.from(ByteBuffer value) {
    final length = value.lengthInBytes;
    final valueList = value.asUint8List();
    if(length <= 2) {
      throw "Invalid byte buffer, length must be bigger than 2";
    }
    if (length - 2 <= max_u7) {
      final header1 = valueList[0];
      final header2 = valueList[1];
      if(header1 == length - 2) {
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
      if(_elementCount.isOdd) {
        _elementCount ++;
      }
      _buffer = ByteData.view(value, 2);
    }
  }

  add(num number, {double precision = 0.0}) {
    assert(precision >= 0.0 && precision <= 0.1, "please set precision as a number between 0.0 and 0.1");
    if (_addNull(number)) {
      return;
    }
    if (number.abs() <= precision) {
      _addU8(0);
      return;
    }
    if (number.isInfinite || number.isNaN) {
      _addF16(number);
      return;
    }
    var intNumber = number.toInt();
    if((intNumber - number).abs() <= precision) {
      if (intNumber.isNegative) {
        if (intNumber >= min_u8) {
          _addI8(number);
        } else if(intNumber >= min_u16) {
          _addI16(intNumber);
        } else if(intNumber >= min_u32) {
          _addI32(intNumber);
        } else {
          _addI64(intNumber);
        }
      } else {
        if (intNumber <= max_u8) {
          _addU8(number);
        } else if(intNumber <= max_u16) {
          _addU16(intNumber);
        } else if(intNumber <= max_u32) {
          _addU32(intNumber);
        } else {
          _addU64(intNumber);
        }
      }
    } else {
      if (precision > 0.0) {
        final f16 = toF16(number);
        if((number - fromF16(f16)).abs() <= precision) {
          _addAsF16AlreadyConvertedValue(f16);
          return;
        }
      }
      if((number - toF32(number)).abs() <= precision) {
        _addF32(number);
      } else {
        _addF64(number);
      }
    }
  }

  addUTF8(String value) {
    if (_addNull(value)) {
      return;
    }
    addBuffer(Uint8List.fromList(utf8.encode(value)).buffer);
  }

  addUTF16(String value, {bool compacted = false}) {
    if (_addNull(value)) {
      return;
    }
    if(Endian.host == _endian) {
      addBuffer(Uint16List.fromList(value.codeUnits).buffer, compacted: compacted);
    } else {
      // need to rotate numbers to represent proper endianness
      final buffer = Uint16List.fromList(value.codeUnits).buffer.asByteData();
      for (var i = 0; i < buffer.lengthInBytes;) {
        final b1 = buffer.getUint8(i);
        final b2 = buffer.getUint8(i+1);
        buffer.setUint8(i, b2);
        buffer.setUint8(i+1, b1);
        i += 2;
      }
      addBuffer(buffer.buffer, compacted: compacted);
    }
  }

  addBuffer(ByteBuffer value, {bool compacted = false}) {
    if (_addNull(value)) {
      return;
    }
    var lengthInBytes = value.lengthInBytes;
    if (lengthInBytes <= 16) {
      _prepareToAppend(lengthInBytes + 1);
      _addTag(BeadType.tinyData);
      _addLengthAsTag(lengthInBytes);
      _copy(from: ByteData.view(value), to: _buffer, offset: _cursor, length: lengthInBytes);
      _cursor += lengthInBytes;
      return;
    }
    if (compacted) {
      final valueAsList = value.asUint8List();
      var compactDataLength = 0;
      var compactData = ByteData((lengthInBytes * 1.125).ceil());
      var flagCursor = 0;
      for (var i = 0; i < lengthInBytes; i++) {
        if(i % 8 == 0) {
          flagCursor = compactDataLength;
          compactDataLength++;
        }
        var byte = valueAsList[i];
        
        if(byte != 0) {
          final bitmask = 1 << (i % 8);
          compactData.setUint8(flagCursor, compactData.getUint8(flagCursor) | bitmask);
          compactData.setUint8(compactDataLength, byte);
          compactDataLength++;
        }
      }
      _prepareToAppend(1);
      _addTag(BeadType.compactData);
      final maxValue = max(lengthInBytes, compactDataLength);
      if (maxValue<= max_u8) {
        _addU8(compactDataLength);
        _prepareToAppend(1);
        _buffer.setUint8(_cursor, lengthInBytes);
        _cursor += 1;
      } else if(maxValue <= max_u16) {
        _addU16(compactDataLength);
        _prepareToAppend(2);
        _buffer.setUint16(_cursor, lengthInBytes);
        _cursor += 2;
      } else if(maxValue <= max_u32) {
        _addU32(compactDataLength);
        _prepareToAppend(4);
        _buffer.setUint32(_cursor, lengthInBytes);
        _cursor += 4;
      } else {
        _addU64(compactDataLength);
        _prepareToAppend(8);
        _buffer.setUint32(_cursor, lengthInBytes);
        _cursor += 8;
      }
      _prepareToAppend(compactDataLength);
      _copy(from: compactData, to: _buffer, offset: _cursor, length: compactDataLength);
      _cursor += compactDataLength;
    } else {
      _prepareToAppend(1);
      _addTag(BeadType.data);
      add(lengthInBytes);
      _prepareToAppend(lengthInBytes);
      _copy(from: ByteData.view(value), to: _buffer, offset: _cursor, length: lengthInBytes);
      _cursor += lengthInBytes;
    }
  }

  void append(BeadsSequence beads) {
    if (_endian != beads._endian) {
      throw "You can only append beads which have same endianness, please consider to add bead after bead";
    }
    if(_elementCount.isOdd) {
      _elementCount++;
    }
    _prepareToAppend(beads._cursor);
    _copy(from: beads._buffer, to: _buffer, offset: _cursor, length: beads._cursor);
    _elementCount += beads._elementCount;
    _cursor += beads._cursor;
    if(_elementCount.isOdd) {
      _elementCount++;
    }
  }

  bool _addNull(value) {
    if (value == null) {
      _prepareToAppend(1);
      _addTag(BeadType.nil);
      return true;
    }
    return false;
  }

  /// Returns a new buffer which contains beads prepended with a header.
  /// Header contains of two numbers:
  /// - Buffer length without the header (beads length)
  /// - Number of elements stored in beads
  /// 
  /// The arrangment of the numbers is endianness dependent (https://en.wikipedia.org/wiki/Endianness).
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
    // Add skip element until the length of buffer is not equal to number of elelments.
    // This is needed because otherwise the reader would not be able to identify the endianness.
    while (_cursor == _elementCount) { 
      _prepareToAppend(1);
      _addTag(BeadType.skip);
    }

    if(_cursor<= max_u7) {
      final bufferCopy = ByteData(_cursor + 2);
      if (_endian == Endian.little) {
        bufferCopy.setUint8(0, _cursor);
        bufferCopy.setUint8(1, _elementCount);
      } else {
        bufferCopy.setUint8(0, _elementCount);
        bufferCopy.setUint8(1, _cursor);
      }
      _copy(from: _buffer, to: bufferCopy, offset: 2, length: _cursor);
      return bufferCopy.buffer;
    } else if(_cursor <= max_u15) {
      final bufferCopy = ByteData(_cursor + 4);
      if (_endian == Endian.little) {
        bufferCopy.setUint16(0, _cursor);
        bufferCopy.setUint16(1, _elementCount);
      } else {
        bufferCopy.setUint16(0, _elementCount);
        bufferCopy.setUint16(1, _cursor);
      }
      _copy(from: _buffer, to: bufferCopy, offset: 4, length: _cursor);
      return bufferCopy.buffer;
    } else if(_cursor <= max_u31) {
      final bufferCopy = ByteData(_cursor + 8);
      if (_endian == Endian.little) {
        bufferCopy.setUint32(0, _cursor);
        bufferCopy.setUint32(1, _elementCount);
      } else {
        bufferCopy.setUint32(0, _elementCount);
        bufferCopy.setUint32(1, _cursor);
      }
      _copy(from: _buffer, to: bufferCopy, offset: 8, length: _cursor);
      return bufferCopy.buffer;
    } else {
      final bufferCopy = ByteData(_cursor + 16);
      if (_endian == Endian.little) {
        bufferCopy.setUint64(0, _cursor);
        bufferCopy.setUint64(1, _elementCount);
      } else {
        bufferCopy.setUint64(0, _elementCount);
        bufferCopy.setUint64(1, _cursor);
      }
      _copy(from: _buffer, to: bufferCopy, offset: 16, length: _cursor);
      return bufferCopy.buffer;
    }
  }

  _addTag(BeadType type) {
    if(_elementCount.isEven) {
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
    assert(length <= 16);
    if(_elementCount.isEven) {
      _flagIndex = _cursor;
      _buffer.setUint8(_flagIndex, length);
      _cursor++;
    } else {
      final prevFlag = _buffer.getUint8(_flagIndex);
      _buffer.setUint8(_flagIndex, prevFlag | (length << 4));
    }
    _elementCount++;
  }

  _addU8(num number) {
    _prepareToAppend(2);
    _addTag(BeadType.u8);
    _buffer.setUint8(_cursor, number);
    _cursor += 1;
  }

  _addU16(num number) {
    _prepareToAppend(3);
    _addTag(BeadType.u16);
    _buffer.setUint16(_cursor, number, _endian);
    _cursor += 2;
  }

  _addU32(num number) {
    _prepareToAppend(5);
    _addTag(BeadType.u32);
    _buffer.setUint32(_cursor, number, _endian);
    _cursor += 4;
  }

  _addU64(num number) {
    _prepareToAppend(9);
    _addTag(BeadType.u64);
    _buffer.setUint64(_cursor, number, _endian);
    _cursor += 8;
  }

  _addI8(num number) {
    _prepareToAppend(2);
    _addTag(BeadType.i8);
    _buffer.setInt8(_cursor, number);
    _cursor += 1;
  }

  _addI16(num number) {
    _prepareToAppend(3);
    _addTag(BeadType.i16);
    _buffer.setInt16(_cursor, number, _endian);
    _cursor += 2;
  }

  _addI32(num number) {
    _prepareToAppend(5);
    _addTag(BeadType.i32);
    _buffer.setInt32(_cursor, number, _endian);
    _cursor += 4;
  }

  _addI64(num number) {
    _prepareToAppend(9);
    _addTag(BeadType.i64);
    _buffer.setInt64(_cursor, number, _endian);
    _cursor += 8;
  }

  _addF16(num number) {
    _prepareToAppend(3);
    _addTag(BeadType.f16);
    _buffer.setUint16(_cursor, toF16(number), _endian);
    _cursor += 2;
  }

  _addAsF16AlreadyConvertedValue(int number) {
    _prepareToAppend(3);
    _addTag(BeadType.f16);
    _buffer.setUint16(_cursor, number, _endian);
    _cursor += 2;
  }

  _addF32(num number) {
    _prepareToAppend(5);
    _addTag(BeadType.f32);
    _buffer.setFloat32(_cursor, number, _endian);
    _cursor += 4;
  }

  _addF64(num number) {
    _prepareToAppend(9);
    _addTag(BeadType.f64);
    _buffer.setFloat64(_cursor, number, _endian);
    _cursor += 8;
  }
  
  _prepareToAppend(int numberOfBytes) {
    final prevLength = _buffer.lengthInBytes;
    if(_cursor + numberOfBytes < prevLength) {
      return;
    }
    var newLength = prevLength;
    while(_cursor + numberOfBytes > newLength) {
      newLength = newLength << 1;
    }
    var newBuffer = ByteData(newLength);
    _copy(from: _buffer, to: newBuffer);
    _buffer = newBuffer;
  }

  static _copy({ @required ByteData from, @required ByteData to, int offset = 0, int length, int offsetFrom = 0}) {
    length ??= (from.lengthInBytes - offsetFrom);
    final lengthTo = to.lengthInBytes;
    final lengthFrom = from.lengthInBytes;
    for (var i = 0; i < length;) {
      final posTo = i+offset;
      final posFrom =  i + offsetFrom;
      
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

  static int toF16(double value) {
    if(value.isNaN) {
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
    var sign = ((f>>16)&0x8000);
    var expo = ((((f&0x7f800000)-0x38000000)>>13)&0x7c00);
    var mant = ((f>>13)&0x03ff);
    return (sign | expo | mant);
  }

  static double fromF16(int value) {
    if(value == 31745) { // 0b0_11111_0000000001
      return double.nan;
    }
    if (value == 64512) { // 0b1_11111_0000000000
      return double.negativeInfinity;
    }
    if (value == 31744) { // 0b0_11111_0000000000
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

  static double toF32(double value) {
    var bdata = new ByteData(4);
    bdata.setFloat32(0, value);
    return bdata.getFloat32(0);
  }

  @override
  Iterator<BeadValue> get iterator => BeadsIterator(_buffer, _elementCount, _endian);
}

class BeadsIterator implements Iterator<BeadValue> {
  final ByteData _buffer;
  final int _elementCount;
  final Endian _endian;
  var _cursor = 0;
  var _valueOffset;
  var _index = 0;
  int _typeFlag;
  BeadType _beadType;
  int _dataLength;
  int _unpackedDataLength;

  BeadsIterator(this._buffer, this._elementCount, this._endian);

  @override
  BeadValue get current => BeadValue(_buffer, _valueOffset, _endian, _beadType, _dataLength, _unpackedDataLength);

  @override
  bool moveNext() {
    _dataLength = null;
    _unpackedDataLength = null;

    if(_index == _elementCount) {
      return false;
    }

    if (_index.isEven){
      _typeFlag = _buffer.getUint8(_cursor);
      _cursor += 1;
      _beadType = BeadType.values[_typeFlag & 0x0f];
    } else {
      _beadType = BeadType.values[_typeFlag >> 4];
    }

    if (_beadType == BeadType.skip) {
      _index++;
      return moveNext();
    }
    if (_beadType == BeadType.nil) {
      _index++;
      return true;
    }
    if (_beadType == BeadType.u8 || _beadType == BeadType.i8) {
      _index++;
      _valueOffset = _cursor;
      _cursor++;
      return true;
    }
    if (_beadType == BeadType.u16 || _beadType == BeadType.i16 || _beadType == BeadType.f16) {
      _index++;
      _valueOffset = _cursor;
      _cursor += 2;
      return true;
    }
    if (_beadType == BeadType.u32 || _beadType == BeadType.i32 || _beadType == BeadType.f32) {
      _index++;
      _valueOffset = _cursor;
      _cursor += 4;
      return true;
    }
    if (_beadType == BeadType.u64 || _beadType == BeadType.i64 || _beadType == BeadType.f64) {
      _index++;
      _valueOffset = _cursor;
      _cursor += 8;
      return true;
    }

    if(_beadType == BeadType.tinyData) {
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

    if (_beadType == BeadType.data || _beadType == BeadType.compactData) {
      _index++;

      BeadType lengthType;
      if (_index.isEven){
        _typeFlag = _buffer.getUint8(_cursor);
        _cursor += 1;
        lengthType = BeadType.values[_typeFlag & 0x0f];
      } else {
        lengthType = BeadType.values[_typeFlag >> 4];
      }
      _index++;
      if (lengthType == BeadType.u8) {
        _dataLength = _buffer.getUint8(_cursor);
        _cursor += 1;
        if (_beadType == BeadType.compactData) {
          _unpackedDataLength = _buffer.getUint8(_cursor);
          _cursor += 1;
        }
      } else if (lengthType == BeadType.u16) {
        _dataLength = _buffer.getUint16(_cursor);
        _cursor += 2;
        if (_beadType == BeadType.compactData) {
          _unpackedDataLength = _buffer.getUint16(_cursor);
          _cursor += 2;
        }
      } else if (lengthType == BeadType.u32) {
        _dataLength = _buffer.getUint32(_cursor);
        _cursor += 4;
        if (_beadType == BeadType.compactData) {
          _unpackedDataLength = _buffer.getUint32(_cursor);
          _cursor += 4;
        }
      } else if (lengthType == BeadType.u64) {
        _dataLength = _buffer.getUint64(_cursor);
        _cursor += 8;
        if (_beadType == BeadType.compactData) {
          _unpackedDataLength = _buffer.getUint64(_cursor);
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

class BeadValue {
  final ByteData _buffer;
  final int _offset;
  final Endian _endian;
  final BeadType _beadType;
  final int _dataLength;
  final int _unpackedDataLength;

  BeadValue(this._buffer, this._offset, this._endian, this._beadType, this._dataLength, this._unpackedDataLength);

  bool get isNil => _beadType == BeadType.nil;
  bool get isInt => 
    _beadType == BeadType.u8 || _beadType == BeadType.i8 || 
    _beadType == BeadType.u16 || _beadType == BeadType.i16 ||
    _beadType == BeadType.u32 || _beadType == BeadType.i32 ||
    _beadType == BeadType.u64 || _beadType == BeadType.i64;
  bool get isDouble => 
    _beadType == BeadType.f16 || _beadType == BeadType.f32 || _beadType == BeadType.f64;
  bool get isNumber => isInt || isDouble;
  bool get isData => 
    _beadType == BeadType.data || _beadType == BeadType.compactData || _beadType == BeadType.tinyData;
  bool get isCompactData => _beadType == BeadType.compactData;

  int get intValue {
    if (_beadType == BeadType.u8) {
      return _buffer.getUint8(_offset);
    } else if (_beadType == BeadType.i8) {
      return _buffer.getInt8(_offset);
    } else if (_beadType == BeadType.u16) {
      return _buffer.getUint16(_offset, _endian);
    } else if (_beadType == BeadType.i16) {
      return _buffer.getInt16(_offset, _endian);
    } else if (_beadType == BeadType.u32) {
      return _buffer.getUint32(_offset, _endian);
    } else if (_beadType == BeadType.i32) {
      return _buffer.getInt32(_offset, _endian);
    } else if (_beadType == BeadType.u64) {
      return _buffer.getUint64(_offset, _endian);
    } else if (_beadType == BeadType.i64) {
      return _buffer.getInt64(_offset, _endian);
    }
    return null;
  }

  double get doubleValue {
    if (_beadType == BeadType.f16) {
      return BeadsSequence.fromF16(_buffer.getUint16(_offset, _endian));
    } else if (_beadType == BeadType.f32) {
      return _buffer.getFloat32(_offset, _endian);
    } else if (_beadType == BeadType.f64) {
      return _buffer.getFloat64(_offset, _endian);
    }
    return null;
  }

  num get number {
    return doubleValue ?? intValue;
  }

  ByteBuffer get data {
    if (_beadType == BeadType.data || _beadType == BeadType.tinyData) {
      ByteData result = ByteData(_dataLength);
      BeadsSequence._copy(from: _buffer, to: result, offsetFrom: _offset, length: _dataLength);
      return result.buffer;
    } else if (_beadType == BeadType.compactData) {
      ByteData unpackedBuffer = ByteData(_unpackedDataLength);
      var elementIndex = 0;
      var cursor = _offset;
      while (elementIndex < _unpackedDataLength && cursor < (_dataLength + _offset)) {
        var tag = _buffer.getUint8(cursor);
        cursor++;
        for (var bitIndex = 0; bitIndex < 8; bitIndex++) {
          var bitmask = 1 << bitIndex;
          if(elementIndex >= _unpackedDataLength) {
            break;
          }
          if (tag & bitmask != 0) {
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

  String get utf8String {
    final data = this.data;
    if(data == null){
      return null;
    }
    return utf8.decode(data.asUint8List());
  }

  String get utf16String {
    return _utf16String(Endian.host);
  }

  String _utf16String(Endian endian) {
    final data = this.data;
    if(data == null || data.lengthInBytes % 2 != 0){
      return null;
    }
    if (endian == _endian) {
      return String.fromCharCodes(data.asUint16List());
    } else {
      final byteData = data.asByteData();
      for (var i = 0; i < data.lengthInBytes; ) {
        var byte1 = byteData.getUint8(i);
        var byte2 = byteData.getUint8(i+1);
        byteData.setUint8(i, byte2);
        byteData.setUint8(i+1, byte1);
        i += 2;
      }
      return String.fromCharCodes(data.asUint16List());
    }
  }
}