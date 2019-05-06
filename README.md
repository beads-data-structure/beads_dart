# beads_dart
[![Build Status](https://travis-ci.org/beads-data-structure/beads_dart.svg?branch=master)](https://travis-ci.org/beads-data-structure/beads_dart)
[![Coverage Status](https://coveralls.io/repos/github/beads-data-structure/beads_dart/badge.svg?branch=master)](https://coveralls.io/github/beads-data-structure/beads_dart?branch=master)

Beads is an append only data structure optimised for memory footprint.
It can be used as a simple way of serialising a sequence of numbers or strings.

While appending numbers to a beads sequence, smallest possible representation is chosen:

__Example 1:__
```dart
final beads = BeadsSequence()
  ..add(1)
  ..add(23453)
  ..add(-34)
  ..add(313)
  ..add(null)
  ..add(0);
assert(beads.buffer.lengthInBytes == 12);
```

As you can see in Example 1, storing 6 numeric values result in a buffer of just 12 bytes.

Beads sequence is `Iterable`. In order to extract values from beads you need to iterate over it, or use the `map` method:

__Example 2:__
```dart
var array = beads.map((value) => value.number);
print(array); // => (1, 23453, -34, 313, null, 0)
```

A beads buffer can be instantiated from a `ByteBuffer` instance.

__Example 3:__
```dart
final beads1 = BeadsSequence()
..add(23)
..add(45);
final beads2 = BeadsSequence.from(beads1.buffer);
print(beads2.map((value)=>value.number)); // => (23, 45)
```

Providing us with a simple way to deserialize a Beads sequence.

We can mix integers, floating-point numbers, `null` values and even strings in the same beads sequence.

__Example 4:__
```dart
final beads = BeadsSequence()
..add(45)
..add(3.1)
..add(null)
..add(-1)
..addUTF8("Maxim")
..add(-13.3);
assert(beads.buffer.lengthInBytes == 29);
```

However we need to be careful when extracting the values from the beads sequence

__Example 5:__
```dart
var array = [];
for (var value in beads){
  if (value.isData) {
    array.add(value.utf8String);
  } else {
    array.add(value.number);
  }
}
print(array); // => [45, 3.1, null, -1, Maxim, -13.3]
```

Thanks to `num` type, we don't have to distinguish between `int` and `double` in Dart. However `String` and Beads is a more complex topic.
In Beads we generally distinguish only between different types of numbers and different representation of data, or `ByteBuffer` if you will.
A string is stored as `data` in a specific encoding. This implementation of Beads allows user to store strings as UTF8 or UTF16.

__Example 6:__
```dart
final beads1 = BeadsSequence()
..addUTF8('Max')
..addUTF8('Alex')
..addUTF8('Maxim');
assert(beads1.buffer.lengthInBytes == 17);

final beads2 = BeadsSequence()
..addUTF16('Max')
..addUTF16('Alex')
..addUTF16('Maxim');
assert(beads2.buffer.lengthInBytes == 29);
```

This however implies that user, who iterates over beads sequence, needs to know which encoding to chose, as `BeadsValue` - the class which provides an access to values has an explicit getter for `utf8String` and `utf16String`.

_Why do we provide two ways of storing string values?_

Mainly because string encoding is not Beads concern. For Beads a string is just an array of bytes (data).
In Dart the strings are internally stored in UTF16 encoding. So adding a string in UTF16 format can be performed without the overhead of value conversion.
However as you can see in __Example 6__. Storing string in UTF16 format is much more wasteful in regards to memory consumption.

## Floating-Point numbers
In Dart a floating-point number is represented in 8 bytes according to IEEE 754 standard (https://en.wikipedia.org/wiki/IEEE_754). Beads can store the floating point numbers in 4 or even 2 bytes, if its representation in lower precision yields a tolerable result.

This implementation of Beads stores `double.nan`, `double.infinity` and `double.negativeInfinity` values in 2 bytes. It also checks if a double value is actually an integer, or tolerably close to an integer value.

I used the word _tolerance_ twice already, but did not explain what I mean by it.

__Example 7:__
```dart
final beads1 = BeadsSequence()
..add(0.001);
assert(beads1.buffer.lengthInBytes == 11);
print(beads1.map((value)=>value.number)); // => (0.001)

final beads2 = BeadsSequence()
  ..add(0.001, tolerance: 0.0000001);
assert(beads2.buffer.lengthInBytes == 7);
print(beads2.map((value)=>value.number)); // => (0.0010000000474974513)

final beads3 = BeadsSequence()
  ..add(0.001, tolerance: 0.000001);
assert(beads3.buffer.lengthInBytes == 5);
print(beads3.map((value)=>value.number)); // => (0.00099945068359375)

final beads4 = BeadsSequence()
  ..add(0.001, tolerance: 0.001);
assert(beads4.buffer.lengthInBytes == 4);
print(beads4.map((value)=>value.number)); // => (0)

final beads5 = BeadsSequence()
  ..add(-0.001, tolerance: 0.001);
assert(beads5.buffer.lengthInBytes == 4);
print(beads5.map((value)=>value.number)); // => (0)
```

The `add` method on `BeadsSequence` has an optional parameter `tolerance` which is set to `0.0` by default.

When we add a number to beads it tries to find a most compact representation for this value. It does so by converting the value to another representation, than subtracting the compact value from the initial value and check if the absolute result is smaller, or equal provided tolerance.
In __Example 7__ we can see that beads buffer which contains value `0.001` as is takes up 11 bytes, but it also keeps the exact precision of the value.

When we define the `tolerance` to be `0.0000001`, the number loses precision, but can be stored as 4byte floating point number.

When we increase the tolerance to `0.000001` the value can be stored as 2byte floating point value. And by setting the `tolerance` to `0.001` we can store the number as 1 byte integer.

## Storing data
When storing data (`ByteBuffer` instances) Beads stores not only the bytes, but also the length of the buffer.

When a buffer is smaller than 16 bytes, the length of the buffer occupies only 4 bits, however there is no posibility to store the bytes in a compacted way.

_What does compacted way means?_

__Example 8:__
```dart
final data1 = Uint8List.fromList([0, 1 , 34, 67, 0, 0, 0, 0, 45, 98, 123, 201, 0, 0, 0]);
final beads1 = BeadsSequence()
..addBuffer(data1.buffer);
expect(beads1.buffer.lengthInBytes, 18);
print(beads1.first.data.asUint8List()); // => [0, 1, 34, 67, 0, 0, 0, 0, 45, 98, 123, 201, 0, 0, 0]

final data2 = Uint8List.fromList([0, 1 , 34, 67, 0, 0, 0, 0, 45, 98, 123, 201, 0, 0, 0, 13]);
final beads2 = BeadsSequence()
  ..addBuffer(data2.buffer);
expect(beads2.buffer.lengthInBytes, 20);
print(beads2.first.data.asUint8List()); // => [0, 1, 34, 67, 0, 0, 0, 0, 45, 98, 123, 201, 0, 0, 0, 13]

final data3 = Uint8List.fromList([0, 1 , 34, 67, 0, 0, 0, 0, 45, 98, 123, 201, 0, 0, 0, 13]);
final beads3 = BeadsSequence()
  ..addBuffer(data3.buffer, compacted: true);
expect(beads3.buffer.lengthInBytes, 15);
print(beads3.first.data.asUint8List()); // => [0, 1, 34, 67, 0, 0, 0, 0, 45, 98, 123, 201, 0, 0, 0, 13]

```

While adding buffer to beads a caller can set option `compacted` parameter to `true`. This parameter instructs Beads evaluate the buffer in chunks of 8 bytes. Every chunk is prepended with a bit mask byte, which reflects which byte in the chunk is bigger than 0. The bytes which are equal to 0 are not stored any more. This technique effectively adds 1byte every 8 bytes to the buffer, but also removes 0 values from the buffer. This means that a compacted buffer can be from 0.125 to 1.125 the size of initial buffer.

In __Example 8__ we see that compaction reduced the overall size of the buffer by 5 bytes, there for we achieved 25% of compression.