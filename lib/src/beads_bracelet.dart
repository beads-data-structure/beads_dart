import 'dart:typed_data';
import 'dart:mirrors';
import 'beads_implementation.dart';

const BeadIndex beadIndex = const BeadIndex();

class BeadIndex {
  final int index;
  const BeadIndex([this.index]);
}

mixin BeadsBracelet {
  BeadsSequence get bracelet {
    final reflection = reflect(this);
    var membersLookup = Map<int, Symbol>();
    int biggestIndex =
        _fillMembersLookupAndBiggestMemberIndex(reflection, membersLookup);
    var beads = BeadsSequence();
    var elementsAdded = 0;
    for (var i = 0; i <= biggestIndex; i++) {
      final symbol = membersLookup[i];
      if (symbol == null) {
        beads.add(null);
        elementsAdded++;
        continue;
      }
      final value = reflection.getField(symbol).reflectee;
      if (value == null) {
        elementsAdded++;
        beads.add(null);
      } else if (value is num) {
        elementsAdded++;
        beads.add(value);
      } else if (value is String) {
        beads.addUTF8(value);
        elementsAdded++;
      } else if (value is BeadsBracelet) {
        final subBracelet = value.bracelet;
        elementsAdded += subBracelet.first.number + 1;
        beads.append(subBracelet);
      } else if (value is bool) {
        elementsAdded++;
        beads.add(
            value ? 1 : 0); // no need to test for null as it is already tested
      } else if (value is ByteBuffer) {
        elementsAdded++;
        beads.addBuffer(value);
      } else if (reflect(value).type.isEnum) {
        final e = value as dynamic;
        elementsAdded++;
        beads.add(e.index as int);
      } else if (value is List<num>) {
        beads.add(value.length);
        for (var item in value) {
          beads.add(item);
        }
        elementsAdded += (value.length + 1);
      } else if (value is List<String>) {
        beads.add(value.length);
        for (var item in value) {
          beads.addUTF8(item);
        }
        elementsAdded += (value.length + 1);
      } else if (value is List<ByteBuffer>) {
        beads.add(value.length);
        for (var item in value) {
          beads.addBuffer(item);
        }
        elementsAdded += (value.length + 1);
      } else if (value is List<bool>) {
        beads.add(value.length);
        for (var item in value) {
          if (item == null) {
            beads.add(null);
          } else {
            beads.add(item ? 1 : 0);
          }
        }
        elementsAdded += (value.length + 1);
      } else if (value is List<BeadsBracelet>) {
        beads.add(value.length);
        for (var item in value) {
          if (item == null) {
            beads.add(null);
            elementsAdded++;
          } else {
            final subBracelet = item.bracelet;
            elementsAdded += subBracelet.first.number + 1;
            beads.append(subBracelet);
          }
        }
        elementsAdded += 1;
      } else if (value is List &&
          (reflect(value).type.typeArguments.first as ClassMirror).isEnum) {
        beads.add(value.length);
        for (var item in value) {
          if (item == null) {
            beads.add(null);
            elementsAdded++;
          } else {
            final e = item as dynamic;
            elementsAdded++;
            beads.add(e.index as int);
          }
        }
        elementsAdded += 1;
      } else if (value is Map) {
        beads.add(value.length);
        elementsAdded++;

        for (var entry in value.entries) {
          final key = entry.key;
          if (key == null) {
            beads.add(null);
          } else if (key is num) {
            beads.add(key);
          } else if (key is String) {
            beads.addUTF8(key);
          } else {
            throw 'Unexpected key type ' + key.runtimeType.toString();
          }
          elementsAdded++;
          final value = entry.value;
          if (value == null) {
            beads.add(null);
          } else if (value is num) {
            beads.add(value);
          } else if (value is String) {
            beads.addUTF8(value);
          } else if (value is bool) {
            beads.add(value ? 1 : 0);
          } else if ((reflect(value).type).isEnum) {
            beads.add((value as dynamic).index as int);
          } else if (value is ByteBuffer) {
            beads.addBuffer(value);
          } else if (value is BeadsBracelet) {
            final subBracelet = value.bracelet;
            elementsAdded += subBracelet.first.number;
            beads.append(subBracelet);
          } else {
            throw 'Unexpected value type ' + value.runtimeType.toString();
          }
          elementsAdded++;
        }
      } else {
        throw 'Unexpected value type ' + value.runtimeType.toString();
      }
    }
    final result = BeadsSequence();
    result.add(elementsAdded);
    result.append(beads);
    return result;
  }

  set bracelet(BeadsSequence beads) {
    final it = beads.iterator;
    _populate(it, false);
  }

  _ObjectAndCount _populate(Iterator<BeadValue> it, bool itOnCount) {
    final reflection = reflect(this);
    var membersLookup = Map<int, Symbol>();
    int biggestIndex =
        _fillMembersLookupAndBiggestMemberIndex(reflection, membersLookup);

    if (itOnCount == false) {
      if (it.moveNext() == false) {
        throw 'Beads sequence is invalid';
      }
    }
    final current = it.current;
    if (current.isNil) {
      return _ObjectAndCount(null, 1);
    }
    final maxCursor = current.number;
    if (maxCursor == null) {
      throw 'Beads sequence is invalid';
    }
    var cursor = 0;
    for (var i = 0; i <= biggestIndex; i++) {
      if (cursor >= maxCursor) {
        // we have an older version where not all properties are provided
        break;
      }
      if (it.moveNext() == false) {
        // return _ObjectAndCount(this, i);
        throw 'Beads sequence is invalid';
      }

      final symbol = membersLookup[i];
      if (symbol == null) {
        // we have an older version with data we don't use any more
        continue;
      }
      var member = reflection.type.declarations[symbol] as VariableMirror;
      if (member.type.isSubtypeOf(reflectType(num))) {
        reflection.setField(symbol, it.current.number);
        cursor++;
      } else if (member.type.isSubtypeOf(reflectType(String))) {
        reflection.setField(symbol, it.current.utf8String);
        cursor++;
      } else if (member.type.isSubtypeOf(reflectType(BeadsBracelet))) {
        final classRef = reflectClass(member.type.reflectedType);
        var instance =
            classRef.newInstance(Symbol(''), []).reflectee as BeadsBracelet;
        var objectAndCount = instance._populate(it, true);
        reflection.setField(symbol, objectAndCount.object);
        cursor += objectAndCount.count;
      } else if (member.type.isSubtypeOf(reflectType(bool))) {
        reflection.setField(symbol, it.current.number == 0 ? false : true);
        cursor++;
      } else if (member.type.isSubtypeOf(reflectType(ByteBuffer))) {
        reflection.setField(symbol, it.current.data);
        cursor++;
      } else if (member.type.isSubtypeOf(reflectType(List))) {
        final length = it.current.number;
        cursor++;
        if (length != null) {
          final classRef = (member.type as ClassMirror);
          var list = classRef.newInstance(Symbol(''), [length]).reflectee;
          if (member.type.typeArguments.first.isSubtypeOf(reflectType(int))) {
            cursor = _populateIntList(length, it, list, cursor);
            reflection.setField(symbol, list);
          } else if (member.type.typeArguments.first
              .isSubtypeOf(reflectType(double))) {
            cursor = _populateDoubleList(length, it, list, cursor);
            reflection.setField(symbol, list);
          } else if (member.type.typeArguments.first
              .isSubtypeOf(reflectType(num))) {
            cursor = _populateNumList(length, it, list, cursor);
            reflection.setField(symbol, list);
          } else if (member.type.typeArguments.first
              .isSubtypeOf(reflectType(String))) {
            cursor = _populateStringList(length, it, list, cursor);
            reflection.setField(symbol, list);
          } else if (member.type.typeArguments.first
              .isSubtypeOf(reflectType(ByteBuffer))) {
            cursor = _populateByteBufferList(length, it, list, cursor);
            reflection.setField(symbol, list);
          } else if (member.type.typeArguments.first
              .isSubtypeOf(reflectType(bool))) {
            cursor = _populateBoolList(length, it, list, cursor);
            reflection.setField(symbol, list);
          } else if (member.type.typeArguments.first
              .isSubtypeOf(reflectType(BeadsBracelet))) {
            cursor =
                _populateBeadsBraceletList(length, it, member, list, cursor);
            reflection.setField(symbol, list);
          } else if ((member.type.typeArguments.first as ClassMirror).isEnum) {
            final enumClassMirror =
                (member.type.typeArguments.first as ClassMirror);
            cursor =
                _populateEnumList(enumClassMirror, length, it, list, cursor);
            reflection.setField(symbol, list);
          } else {
            throw 'Unexpected List type ' +
                member.type.typeArguments.first.toString();
          }
        }
      } else if (member.type.isSubtypeOf(reflectType(Map))) {
        final length = it.current.number;
        cursor++;
        if (length != null) {
          final map = (member.type as ClassMirror)
              .newInstance(Symbol(''), []).reflectee;
          for (var i = 0; i < length; i++) {
            if (it.moveNext() == false) {
              throw 'Beads sequence is invalid';
            }
            var key;
            final keyType = member.type.typeArguments.first;
            if (keyType.isSubtypeOf(reflectType(int))) {
              key = it.current.number.toInt();
            } else if (keyType.isSubtypeOf(reflectType(double))) {
              key = it.current.number.toDouble();
            } else if (keyType.isSubtypeOf(reflectType(num))) {
              key = it.current.number;
            } else if (keyType.isSubtypeOf(reflectType(String))) {
              key = it.current.utf8String;
            } else {
              throw 'Unexpected key type ' + keyType.toString();
            }
            cursor++;
            if (it.moveNext() == false) {
              throw 'Beads sequence is invalid';
            }
            var value;
            final valueType = (member.type.typeArguments[1] as ClassMirror);
            if (it.current.isNil) {
              value = null;
            } else if (valueType.isSubtypeOf(reflectType(int))) {
              value = it.current.number.toInt();
            } else if (valueType.isSubtypeOf(reflectType(double))) {
              value = it.current.number.toDouble();
            } else if (valueType.isSubtypeOf(reflectType(num))) {
              value = it.current.number;
            } else if (valueType.isSubtypeOf(reflectType(String))) {
              value = it.current.utf8String;
            } else if (valueType.isSubtypeOf(reflectType(bool))) {
              value = it.current.number == 1 ? true : false;
            } else if (valueType.isSubtypeOf(reflectType(ByteBuffer))) {
              value = it.current.data;
            } else if (valueType.isSubtypeOf(reflectType(BeadsBracelet))) {
              var instance = valueType.newInstance(Symbol(''), []).reflectee;
              var objectAndCount = instance._populate(it, true);
              value = objectAndCount.object;
              cursor += objectAndCount.count;
            } else if (valueType.isEnum) {
              final enumValues = valueType.getField(#values).reflectee;
              final index = it.current.number;
              if (index != null && index < enumValues.length) {
                // important for forwards compatibility on enums
                // a new case could be introduced which will result in `null`
                value = enumValues[index];
              } else {
                value = null;
              }
            } else {
              throw 'Unexpected value type ' + valueType.toString();
            }
            cursor++;
            map[key] = value;
          }
          reflection.setField(symbol, map);
        }
      } else if (reflectClass(member.type.reflectedType).isEnum) {
        final enumValues =
            (member.type as ClassMirror).getField(#values).reflectee;
        final index = it.current.number;
        if (index != null && index < enumValues.length) {
          // important for forwards compatibility on enums
          // a new case could be introduced which will result in `null`
          reflection.setField(symbol, enumValues[index]);
        }
        cursor++;
      } else {
        throw 'Unexpected type ' + member.type.simpleName.toString();
      }
    }

    while (cursor < maxCursor) {
      // we have a new version skip unknown data portion
      it.moveNext();
      cursor++;
    }

    return _ObjectAndCount(this, cursor + 1);
  }
}

int _populateIntList(num length, Iterator<BeadValue> it, list, int cursor) {
  for (var i = 0; i < length; i++) {
    if (it.moveNext() == false) {
      throw 'Beads sequence is invalid';
    }
    list[i] = it.current.number?.toInt();
    cursor++;
  }
  return cursor;
}

int _populateDoubleList(num length, Iterator<BeadValue> it, list, int cursor) {
  for (var i = 0; i < length; i++) {
    if (it.moveNext() == false) {
      throw 'Beads sequence is invalid';
    }
    list[i] = it.current.number?.toDouble();
    cursor++;
  }
  return cursor;
}

int _populateNumList(num length, Iterator<BeadValue> it, list, int cursor) {
  for (var i = 0; i < length; i++) {
    if (it.moveNext() == false) {
      throw 'Beads sequence is invalid';
    }
    list[i] = it.current.number;
    cursor++;
  }
  return cursor;
}

int _populateStringList(num length, Iterator<BeadValue> it, list, int cursor) {
  for (var i = 0; i < length; i++) {
    if (it.moveNext() == false) {
      throw 'Beads sequence is invalid';
    }
    list[i] = it.current.utf8String;
    cursor++;
  }
  return cursor;
}

int _populateByteBufferList(
    num length, Iterator<BeadValue> it, list, int cursor) {
  for (var i = 0; i < length; i++) {
    if (it.moveNext() == false) {
      throw 'Beads sequence is invalid';
    }
    list[i] = it.current.data;
    cursor++;
  }
  return cursor;
}

int _populateBoolList(num length, Iterator<BeadValue> it, list, int cursor) {
  for (var i = 0; i < length; i++) {
    if (it.moveNext() == false) {
      throw 'Beads sequence is invalid';
    }
    if (it.current.isNumber) {
      list[i] = it.current.number == 0 ? false : true;
    } else {
      list[i] = null;
    }
    cursor++;
  }
  return cursor;
}

int _populateEnumList(ClassMirror enumClassMirror, num length,
    Iterator<BeadValue> it, list, int cursor) {
  final enumValues = enumClassMirror.getField(#values).reflectee;
  for (var i = 0; i < length; i++) {
    if (it.moveNext() == false) {
      throw 'Beads sequence is invalid';
    }
    final index = it.current.number;
    if (index != null && index < enumValues.length) {
      // important for forwards compatibility on enums
      // a new case could be introduced which will result in `null`
      list[i] = enumValues[index];
    } else {
      list[i] = null;
    }
    cursor++;
  }
  return cursor;
}

int _populateBeadsBraceletList(num length, Iterator<BeadValue> it,
    VariableMirror member, list, int cursor) {
  for (var i = 0; i < length; i++) {
    if (it.moveNext() == false) {
      throw 'Beads sequence is invalid';
    }
    final classRef =
        reflectClass(member.type.typeArguments.first.reflectedType);
    var instance = classRef.newInstance(Symbol(''), []).reflectee;
    var objectAndCount = instance._populate(it, true);
    list[i] = objectAndCount.object;
    cursor += objectAndCount.count;
  }
  return cursor;
}

class _ObjectAndCount {
  final dynamic object;
  final int count;
  _ObjectAndCount(this.object, this.count);
}

int _fillMembersLookupAndBiggestMemberIndex(
    InstanceMirror refelction, Map<int, Symbol> membersLookup) {
  var biggestIndex = 0;
  for (var memeberKey in refelction.type.declarations.keys) {
    var member = refelction.type.declarations[memeberKey];
    if (member is VariableMirror) {
      for (var meta in member.metadata) {
        if (meta.type.isSubtypeOf(reflectType(BeadIndex))) {
          int index = meta.getField(#index).reflectee;
          if (index == null || index < 0) {
            throw 'Index has to be an int, bigger or equal to 0. ' +
                membersLookup[index].toString() +
                ' does not confirm to this restriction';
          }
          if (membersLookup.containsKey(index)) {
            throw 'Members ' +
                memeberKey.toString() +
                ' and ' +
                membersLookup[index].toString() +
                ' has the same index ' +
                index.toString();
          }
          membersLookup[index] = memeberKey;
          if (index > biggestIndex) {
            biggestIndex = index;
          }
        }
      }
    }
  }
  return biggestIndex;
}
