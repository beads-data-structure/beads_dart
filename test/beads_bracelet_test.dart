import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:beads/beads.dart';

class A with BeadsBracelet {
  @BeadIndex(0)
  String name;
  @BeadIndex(1)
  int age;
  @BeadIndex(2)
  A friend;
  bool operator ==(o) =>
      o is A && o.name == name && o.age == age && o.friend == friend;
  int get hashCode => name.hashCode ^ age.hashCode ^ friend.hashCode;
}

class A1 with BeadsBracelet {
  @BeadIndex(0)
  String name;
  @BeadIndex(1)
  int age;
  @BeadIndex(2)
  A1 friend;
  @BeadIndex(3)
  String nickName;
}

enum Gender { male, female, other }

class B with BeadsBracelet {
  @BeadIndex(0)
  bool b;
  @BeadIndex(1)
  int i;
  @BeadIndex(2)
  double d;
  @BeadIndex(3)
  String s;
  @BeadIndex(4)
  A a;
  @BeadIndex(5)
  Gender g;
  @BeadIndex(6)
  List<int> li;
  @BeadIndex(7)
  List<bool> lb;
  @BeadIndex(8)
  List<double> ld;
  @BeadIndex(9)
  List<num> ln;
  @BeadIndex(10)
  List<A> la;
  @BeadIndex(11)
  Map<String, bool> msb;
  @BeadIndex(12)
  Map<String, int> msi;
  @BeadIndex(13)
  Map<String, double> msd;
  @BeadIndex(14)
  Map<String, num> msn;
  @BeadIndex(15)
  Map<String, String> mss;
  @BeadIndex(16)
  Map<String, A> msa;
  @BeadIndex(17)
  Map<num, int> mii;
  @BeadIndex(18)
  Map<num, double> mid;
  @BeadIndex(19)
  Map<num, num> min;
  @BeadIndex(20)
  Map<num, String> mis;
  @BeadIndex(21)
  Map<num, A> mia;
  @BeadIndex(22)
  List<Gender> lg;
  @BeadIndex(23)
  Map<String, Gender> msg;
  @BeadIndex(24)
  Map<num, Gender> mig;
  @BeadIndex(25)
  List<String> ls;
  @BeadIndex(26)
  ByteBuffer bb;
  @BeadIndex(27)
  List<ByteBuffer> lbb;
  @BeadIndex(28)
  Map<String, ByteBuffer> msbb;
  @BeadIndex(29)
  Map<num, ByteBuffer> mibb;
  @BeadIndex(30)
  Map<num, bool> mib;
}

class E1 with BeadsBracelet {
  @BeadIndex()
  int i;
}

class E2 with BeadsBracelet {
  @BeadIndex(1)
  int i;
  @BeadIndex(1)
  int j;
}

class F with BeadsBracelet {
  @BeadIndex(1)
  int i;
  @BeadIndex(5)
  int j;
}

class G with BeadsBracelet {
  @BeadIndex(0)
  Map<int, String> strings1;
  @BeadIndex(1)
  Map<double, String> strings2;
}

void main() {
  test('Bracelet from BeadsBracelet class', () {
    var a = A();
    a.name = 'Max';
    a.age = 38;
    a.friend = A()
      ..age = 45
      ..name = 'Alex';

    var newA = A();
    newA.bracelet = a.bracelet;
    expect(newA.age, 38);
    expect(newA.name, 'Max');
    expect(newA.friend.age, 45);
    expect(newA.friend.name, 'Alex');
  });

  test('Bracelet backwards compatibility', () {
    var a = A();
    a.name = 'Max';
    a.age = 38;
    a.friend = A()
      ..age = 45
      ..name = 'Alex';

    var newA = A1();
    newA.bracelet = a.bracelet;
    expect(newA.age, 38);
    expect(newA.name, 'Max');
    expect(newA.nickName, null);
    expect(newA.friend.age, 45);
    expect(newA.friend.name, 'Alex');
    expect(newA.friend.nickName, null);
  });

  test('Bracelet forward compatibility', () {
    var a = A1();
    a.name = 'Max';
    a.age = 38;
    a.nickName = 'mz';
    a.friend = A1()
      ..age = 45
      ..name = 'Alex'
      ..nickName = 'aa';

    var newA = A();
    newA.bracelet = a.bracelet;
    expect(newA.age, 38);
    expect(newA.name, 'Max');
    expect(newA.friend.age, 45);
    expect(newA.friend.name, 'Alex');
  });

  test('Bracelet with number string enum and bool', () {
    var b = B();
    b.i = 13;
    b.d = 3.5;
    b.b = true;
    b.s = "Hello";
    b.g = Gender.other;
    var newB = B();
    newB.bracelet = b.bracelet;

    expect(newB.i, b.i);
    expect(newB.d, b.d);
    expect(newB.b, b.b);
    expect(newB.s, b.s);
    expect(newB.g, b.g);
  });

  test('Bracelet with list of numbers and strings', () {
    var b = B();
    b.li = [1, 2, null, -3, 0];
    b.ln = [1.5, 5, -9, null];
    b.ld = [0.1, -0.5, null, 0.0];
    b.ls = ["Max", null, "Alex"];
    var newB = B();
    newB.bracelet = b.bracelet;

    expect(newB.li, b.li);
    expect(newB.ln, b.ln);
    expect(newB.ld, b.ld);
    expect(newB.ls, b.ls);
  });

  test('Bracelet with list of bools', () {
    var b = B();
    b.lb = [true, false, true, null, true];
    var newB = B();
    newB.bracelet = b.bracelet;

    expect(newB.lb, b.lb);
  });

  test('Bracelet with list of enums', () {
    var b = B();
    b.lg = [Gender.female, Gender.male, null, Gender.other];
    var newB = B();
    newB.bracelet = b.bracelet;

    expect(newB.lb, b.lb);
  });

  test('Bracelet with byte buffer', () {
    var b = B();
    b.bb = Uint8List(5).buffer;
    var newB = B();
    newB.bracelet = b.bracelet;
    expect(newB.bb.asUint8List(), b.bb.asUint8List());
  });

  test('Bracelet with byte buffer list', () {
    var b = B();
    b.lbb = [Uint8List(5).buffer, null, Uint8List(7).buffer];
    var newB = B();
    newB.bracelet = b.bracelet;
    expect(newB.lbb.map((v) => v?.asUint8List()),
        b.lbb.map((v) => v?.asUint8List()));
  });

  test('Bracelet with list of bead bracelet types', () {
    var b = B();
    var a1 = A()
      ..age = 33
      ..name = "Max";
    var a2 = A()
      ..age = 23
      ..name = "Maxim"
      ..friend = a1;
    b.la = [a1, null, a2];

    var newB = B();
    newB.bracelet = b.bracelet;

    expect(newB.la, b.la);
  });

  test('Bracelet from bad class where BeadIndex has no value', () {
    var exceptionCatched = false;
    try {
      var e = E1();
      e.bracelet;
    } catch (e) {
      exceptionCatched = true;
    }

    expect(exceptionCatched, true);
  });

  test('Bracelet from bad class where two fields have same BeadIndex value',
      () {
    var exceptionCatched = false;
    try {
      var e = E2();
      e.bracelet;
    } catch (e) {
      exceptionCatched = true;
    }

    expect(exceptionCatched, true);
  });

  test('Bracelet with class where bead index is not contiguous', () {
    var f = F()
      ..i = 33
      ..j = 45;

    var newF = F();
    newF.bracelet = f.bracelet;

    expect(newF.i, f.i);
    expect(newF.j, f.j);
  });

  test('Bracelet with map from string to numbers, bools and strings', () {
    final b = B();
    b.msb = {'a': true, 'b': false, 'c': null, 'd': true};
    b.msd = {'a': -0.3, 'b': 45.0, 'c': null, 'd': double.infinity, 'e': 13};
    b.msi = {'a': -3, 'b': 45, 'c': null, 'e': 1 << 34};
    b.msn = {'a': -0.3, 'b': 45.0, 'c': null, 'd': double.infinity, 'e': 13};
    b.mss = {'a': 'Max', 'b': null, 'c': 'Alex'};
    b.msg = {'a': Gender.other, 'b': null, 'c': Gender.female};
    final newB = B();
    newB.bracelet = b.bracelet;

    expect(newB.msb, b.msb);
    expect(newB.msd, b.msd);
    expect(newB.msi, b.msi);
    expect(newB.msn, b.msn);
    expect(newB.mss, b.mss);
    expect(newB.msg, b.msg);
  });

  test('Bracelet with map from string to byte buffer', () {
    final b = B();
    b.msbb = {
      'a': Uint8List(5).buffer,
      'c': null,
      'd': Uint8List.fromList([0, 1, 6]).buffer
    };
    final newB = B();
    newB.bracelet = b.bracelet;

    expect(newB.msbb.map((k, v) => MapEntry(k, v?.asUint8List())),
        b.msbb.map((k, v) => MapEntry(k, v?.asUint8List())));
  });

  test('Bracelet with map from string to beads bracelet type', () {
    final b = B();
    final a1 = A()
      ..name = 'Alex'
      ..age = 12;
    final a2 = A()
      ..name = 'Mox'
      ..age = 56
      ..friend = a1;
    b.msa = {'a': a1, 'c': null, 'd': a2};
    final newB = B();
    newB.bracelet = b.bracelet;

    expect(newB.msa, b.msa);
  });

  test('Bracelet with map from int to numbers, bools and strings', () {
    final b = B();
    b.mib = {1: true, 4: false, 9: null, -15: true};
    b.mid = {45: -0.3, 13: 45.0, 1: null, 4: double.infinity, 9: 13};
    b.mii = {46: -3, -90: 45, 11: null, 13: 1 << 34};
    b.min = {40: -0.3, 35: 45.0, 91: null, 32: double.infinity, 11: 13};
    b.mis = {1: 'Max', 2: null, 3: 'Alex'};
    b.msg = {'a': Gender.other, 'b': null, 'c': Gender.female};
    final newB = B();
    newB.bracelet = b.bracelet;

    expect(newB.mib, b.mib);
    expect(newB.mid, b.mid);
    expect(newB.mii, b.mii);
    expect(newB.min, b.min);
    expect(newB.mis, b.mis);
    expect(newB.mig, b.mig);
  });

  test('Bracelet with map from int to byte buffer', () {
    final b = B();
    b.mibb = {
      1: Uint8List(5).buffer,
      3: null,
      2: Uint8List.fromList([0, 1, 6]).buffer
    };
    final newB = B();
    newB.bracelet = b.bracelet;

    expect(newB.mibb.map((k, v) => MapEntry(k, v?.asUint8List())),
        b.mibb.map((k, v) => MapEntry(k, v?.asUint8List())));
  });

  test('Bracelet with map from int to to beads bracelet type', () {
    final b = B();
    final a1 = A()
      ..name = 'Alex'
      ..age = 12;
    final a2 = A()
      ..name = 'Mox'
      ..age = 56
      ..friend = a1;
    b.mia = {1: a1, 5: null, 3: a2};
    final newB = B();
    newB.bracelet = b.bracelet;

    expect(newB.mia, b.mia);
  });

  test('Bracelet with map from double to numbers, bools and strings', () {
    final b = B();
    b.mib = {0.1: true, 0.4: false, 9: null, -15: true};
    b.mid = {45.1: -0.3, 13.8: 45.0, 1: null, 4: double.infinity, 9: 13};
    b.mii = {46: -3, -90: 45, 11.1: null, 13: 1 << 34};
    b.min = {40: -0.3, 35: 45.0, 91.4: null, 32: double.infinity, 11: 13};
    b.mis = {1: 'Max', 2: null, 3.3: 'Alex'};
    b.msg = {'a': Gender.other, 'b': null, 'c': Gender.female};
    final newB = B();
    newB.bracelet = b.bracelet;

    expect(newB.mib, b.mib);
    expect(newB.mid, b.mid);
    expect(newB.mii, b.mii);
    expect(newB.min, b.min);
    expect(newB.mis, b.mis);
    expect(newB.mig, b.mig);
  });

  test('Bracelet with map from double to byte buffer', () {
    final b = B();
    b.mibb = {
      1.1: Uint8List(5).buffer,
      3: null,
      2: Uint8List.fromList([0, 1, 6]).buffer
    };
    final newB = B();
    newB.bracelet = b.bracelet;

    expect(newB.mibb.map((k, v) => MapEntry(k, v?.asUint8List())),
        b.mibb.map((k, v) => MapEntry(k, v?.asUint8List())));
  });

  test('Bracelet with map from float to to beads bracelet type', () {
    final b = B();
    final a1 = A()
      ..name = 'Alex'
      ..age = 12;
    final a2 = A()
      ..name = 'Mox'
      ..age = 56
      ..friend = a1;
    b.mia = {1: a1, 5.2: null, 3: a2};
    final newB = B();
    newB.bracelet = b.bracelet;

    expect(newB.mia, b.mia);
  });

  test('Bracelet with maps where keys are ints and double and not just num',
      () {
    final g = G();
    g.strings1 = {1: "hi", 2: null, 45: "world"};
    g.strings2 = {1.1: "hi", 2: null, 45: "world"};

    final newG = G();
    newG.bracelet = g.bracelet;
    expect(newG.strings1.length, 3);
    expect(newG.strings2.length, 3);
    expect(newG.strings1, g.strings1);
    expect(newG.strings2, g.strings2);
  });
}
