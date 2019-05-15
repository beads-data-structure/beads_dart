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

## Storing object graph
Beads is designed to store values as a seuquence. However in our day to day work we often work with classes and objects. This is why Beads has a object serialisation strategy which is called __Beads Bracelet__.

In order to convert an instance of the class to __Beads Bracelet__ you need to define a class with a `BeadsBracelet` mixin and annotate the fields which hold the data you want to serialise with `BeadIndex`.

__Example 9:__
```dart
class A with BeadsBracelet {
  @BeadIndex(0)
  String name;
  @BeadIndex(1)
  int age;
  @BeadIndex(2)
  A friend;
}

var a1 = new A() .. name = 'Max' .. age = 37;
var a2 = new A() .. name = 'Alex' .. age = 40 .. friend = a1;
var a3 = A();
a3.bracelet = a2.bracelet;

print(a1.bracelet.buffer.asUint8List()); // [8, 6, 1, 3, 60, 77, 97, 120, 241, 37]
print(a2.bracelet.buffer.asUint8List()); // [17, 12, 1, 6, 76, 65, 108, 101, 120, 1, 40, 1, 3, 60, 77, 97, 120, 241, 37]
print(a3.bracelet.buffer.asUint8List()); // [17, 12, 1, 6, 76, 65, 108, 101, 120, 1, 40, 1, 3, 60, 77, 97, 120, 241, 37]
print(a3.name); // Alex
```

`BeadsBracelet` mixin provides property `bracelet` with a getter and setter to our class.

When we call the `bracelet` getter, we get an instance of `BeadsSequence` which holds all the data from the annotated fields. When we invoke the `bracelet` setter with a `BeadsSequence` instance, it overrides all the values with values stored in the sequence.

This is a very easy to use and intuitive aproach for object graph serialisation and deserialisation. However it is based on runtime reflection. In the future it is imaginable to introduce a code geenration aprroach, which should be more run time efficient.

We currently support following types to be serialisable field types:
- `num` / `int` / `double`
- `bool`
- `String`
- `ByteBuffer`
- custom `enum` definitions
- a class with `BeadsBracelet` mixin
- `List` where value type is one of the above
- `Map` where key is `num` / `int` / `double` / `String` and value is one of the above except `List`

__Beads Bracelet__ is designed to be [forward](https://en.wikipedia.org/wiki/Forward_compatibility) and [backward](https://en.wikipedia.org/wiki/Backward_compatibility) compatible. However in order to achieve compatibility you need to follow some rules:
1. It is ok to rename field names, because we store only the values in the order of `BeadIndex`.
2. It is ok to introduce new fields as long as you use new index value in `BeadIndex`.
3. It is ok to deprecate / remove fields as long as you ensure that their `BeadIndex` will not be reused later on.

__Example 10:__
```dart
class Person with BeadsBracelet {
  @BeadIndex(0)
  String name;
  @BeadIndex(1)
  String town;
}
class FullName with BeadsBracelet {
  String firstName;
  String lastName;
}
class Person2 with BeadsBracelet {
  @BeadIndex(0)
  @deprecated
  String deprecated_name;
  @BeadIndex(1)
  String city;
  @BeadIndex(2)
  FullName name;
}

final max1 = Person() .. name = 'Max' .. town = 'Berlin';
final max2 = Person2();
max2.bracelet = max1.bracelet;
print(max2.city); // Berli
print(max2.name); // null
print(max2.deprecated_name); // Max

final max3 = Person2() .. name = (FullName() .. firstName = 'Maxim' .. lastName = 'Zaks') .. city = 'Berlin';
final max4 = Person();
max4.bracelet = max3.bracelet;

print(max4.name); // null
print(max4.town); // Berlin
```

In __Example 10__ `Person2` is an evolution of the `Person` class (normally you would keep the class name). In `Person` we have two fields `name` and `town`. In the next version of `Person` we decided to rename `town` to `city` (which is a non breaking change) and we decided to chenge the type of the `name` moving it from a `String` to a dedicated class. This is normally a breaking change, but with __Beads Bracelet__ we can just rename the old `name` and introduce a new `name` field with desiered type and a new `BeadIndex` value.

Speaking of `BeadIndex`, the `BeadIndex` values you provide should be contiguous as when a bracelet is created, an object will become a sequence of properties sorted by its index. If we have a gap between indexies, say we have two properties with `@BeadIndex(0)` and `@BeadIndex(3)`, than the beads sequence will have 4 elements, where element at index `1` and `2` will be a `null` value, which occupy 4bits in the buffer.