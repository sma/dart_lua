// Copyright 2013, 2020 Stefan Matthias Aust. Licensed under MIT (http://opensource.org/licenses/MIT)
import 'dart:math' show pow;

// ignore_for_file: prefer_single_quotes

/*
 * This is a parser and runtime system for Lua 5.x which lacks most if not all of the Lua standard library.
 * I created the parser a couple of years ago and now ported it to Dart just to see how difficult it would be.
 */

void main() {
  var env = Env(null);
  env.bind("print", (List args) => [print(args[0])]);
  env.eval(Parser(Scanner("print('hello')")).block());
  env.eval(Parser(Scanner("print(3 + 4)")).block());
  env.eval(Parser(Scanner("for i = 0, 5 do print(i) end")).block());
  env.eval(
      Parser(Scanner("function fac(n) if n == 0 then return 1 end; return n * fac(n - 1) end; print(fac(6))")).block());
  env.eval(Parser(Scanner("print({}); print({1, 2}); print({a=1, ['b']=2})")).block());
  env.eval(Parser(Scanner("print(#{1, [2]=2, [4]=4, n=5})")).block());
  env.eval(Parser(Scanner("local a, b = 3, 4; a, b = b, a; print(a..' '..b)")).block());
  env.eval(Parser(Scanner("function v(a, ...) return ... end; print(v(1, 2, 3))")).block());
  env.eval(Parser(Scanner("function v() return 1, 2 end; local a, b = v(); print(b)")).block());
  env.eval(Parser(Scanner("function a(x,y) return x+y end; function b() return 3,4 end; print(a(b()))")).block());
  env.eval(Parser(Scanner("local c = {}; function c:m() return self.b end; print(c.m); c.b=42; print(c:m())")).block());
}

// --------------------------------------------------------------------------------------------------------------------
// Runtime system
// --------------------------------------------------------------------------------------------------------------------

/// Tables are Lua's main datatype: an associative array with an optional metatable describing the table's behavior.
class Table {
  final fields = <dynamic, dynamic>{};
  Table? metatable;

  Table();
  Table.from(Iterable<dynamic> i) {
    var j = 1;
    i.forEach((e) => fields[j++] = e);
  }

  dynamic operator [](dynamic k) => fields[k];
  operator []=(dynamic k, dynamic v) => fields[k] = v;
  int get length {
    var i = 0;
    while (this[i + 1] != null) {
      i++;
    }
    return i;
  }

  @override
  String toString() => fields.toString();
}

/// Functions are defined by the user and bound to the environment.
class Function_ {
  final Env env;
  final List<String> params;
  final Block block;

  Function_(this.env, this.params, this.block);

  List<dynamic> call(List<dynamic> args) {
    var newEnv = Env(env);

    // bind arguments to parameters
    params.asMap().forEach((index, name) {
      if (name == "...") {
        newEnv.bind(name, Table.from(args.sublist(index)));
      } else {
        newEnv.bind(name, index < args.length ? args[index] : null);
      }
    });

    // execute body
    try {
      newEnv.eval(block);
    } on ReturnException catch (e) {
      return e.args;
    }
    return [];
  }

  @override
  String toString() => '<func>';
}

/// Common function type for built-in functions and user defined functions.
/// Notice that functions should always return a List of results.
typedef Fun = List<dynamic> Function(List<dynamic> args);

/// Environments are used to keep variable bindings and evaluate AST nodes.
class Env {
  final Env? parent;
  final Map vars = <String, dynamic>{};

  Env(this.parent);

  // variables

  void bind(String name, dynamic value) {
    vars[name] = value;
  }

  void update(String name, dynamic value) {
    if (vars.containsKey(name)) {
      vars[name] = value;
    } else if (parent != null) {
      parent!.update(name, value);
    } else {
      throw "assignment to unknown variable $name";
    }
  }

  dynamic lookup(String name) {
    if (vars.containsKey(name)) {
      return vars[name];
    } else if (parent != null) {
      return parent!.lookup(name);
    }
    throw "reference of unknown variable $name";
  }

  dynamic eval(Node node) => node.eval(this);

  List<dynamic> evalToList(List<Exp> exps) {
    if (exps.isNotEmpty) {
      var last = exps[exps.length - 1];
      if (last is Call) {
        return exps.sublist(0, exps.length - 1).map((e) => eval(e)).toList()..addAll(last.evalList(this));
      }
    }
    return exps.map((e) => eval(e)).toList();
  }

  bool isTrue(dynamic value) => value != null && value != false;

  // built-in operations

  /// Adds two values (see §2.8).
  static dynamic addEvent(dynamic op1, dynamic op2) {
    if (op1 is num && op2 is num) {
      return op1 + op2;
    }
    return performBinEvent(op1, op2, "__add", "add");
  }

  /// Subtracts two values (see §2.8).
  static dynamic subEvent(dynamic op1, dynamic op2) {
    if (op1 is num && op2 is num) {
      return op1 - op2;
    }
    return performBinEvent(op1, op2, "__sub", "subtract");
  }

  /// Multiplies two values (see §2.8).
  static dynamic mulEvent(dynamic op1, dynamic op2) {
    if (op1 is num && op2 is num) {
      return op1 * op2;
    }
    return performBinEvent(op1, op2, "__mul", "multiply");
  }

  /// Divides two values (see §2.8).
  static dynamic divEvent(dynamic op1, dynamic op2) {
    if (op1 is num && op2 is num) {
      return op1 / op2;
    }
    return performBinEvent(op1, op2, "__div", "divide");
  }

  /// Applies "modulo" two values (see §2.8).
  static dynamic modEvent(dynamic op1, dynamic op2) {
    if (op1 is num && op2 is num) {
      return op1 % op2;
    }
    return performBinEvent(op1, op2, "__mod", "modulo");
  }

  /// Applies "power" to two values (see §2.8).
  static dynamic powEvent(dynamic op1, dynamic op2) {
    if (op1 is num && op2 is num) {
      return pow(op1, op2);
    }
    return performBinEvent(op1, op2, "__pow", "power");
  }

  /// Applies unary minus (see §2.8).
  static dynamic unmEvent(dynamic op) {
    if (op is num) {
      return -op;
    }
    return performUnEvent(op, "__unm", "unary minus");
  }

  /// Concatenates two values (see §2.8).
  static dynamic concatEvent(dynamic op1, dynamic op2) {
    if ((op1 is num || op1 is String) && (op2 is num || op2 is String)) {
      return "$op1$op2";
    }
    return performBinEvent(op1, op2, "__concat", "concat");
  }

  /// Applies length (see §2.8).
  static dynamic lenEvent(dynamic op) {
    if (op is String) {
      return op.length;
    }
    var h = metatable(op, "__len");
    if (h != null) {
      return call1(h, [op]);
    }
    if (op is Table) {
      return op.length;
    }
    throw error("cannot apply length to $op");
  }

  /// Compares two values (see §2.8).
  static bool eqEvent(dynamic op1, dynamic op2) {
    if (op1 == op2) {
      return true;
    }
    var h = getequalhandler(op1, op2, "__eq");
    if (h != null) {
      return call1(h, [op1, op2]) as bool;
    }
    return false;
  }

  /// Compares two values (see §2.8).
  static bool ltEvent(dynamic op1, dynamic op2) {
    if (op1 is num && op2 is num) {
      return op1 < op2;
    }
    if (op1 is String && op2 is String) {
      return op1.compareTo(op2) < 0;
    }
    var h = getbinhandler(op1, op2, "__lt");
    if (h != null) {
      return call1(h, [op1, op2]) as bool;
    }
    throw error("cannot compute $op1 < $op2");
  }

  /// Compares two values (see §2.8).
  static bool leEvent(dynamic op1, dynamic op2) {
    if (op1 is num && op2 is num) {
      return op1 <= op2;
    }
    if (op1 is String && op2 is String) {
      return op1.compareTo(op2) <= 0;
    }
    var h = getbinhandler(op1, op2, "__le");
    if (h != null) {
      return call1(h, [op1, op2]) as bool;
    }
    h = getbinhandler(op1, op2, "__lt");
    if (h != null) {
      return !(call1(h, [op2, op1]) as bool);
    }
    throw error("cannot compute $op1 <= $op2");
  }

  /// Accesses a table field by key (see §2.8).
  static dynamic indexEvent(dynamic table, dynamic key) {
    dynamic h;
    if (table is Table) {
      var v = table[key];
      if (v != null) {
        return v;
      }
      h = metatable(table, "__index");
      if (h == null) {
        return null;
      }
    } else {
      h = metatable(table, "__index");
      if (h == null) {
        throw error("cannot access $table[$key]");
      }
    }
    if (h is Fun) {
      return call1(h, [table, key]);
    }
    return indexEvent(h, key);
  }

  /// Assigns a table field to a new value (see §2.8).
  static void newindexEvent(dynamic table, dynamic key, dynamic value) {
    dynamic h;
    if (table is Table) {
      var v = table[key];
      if (v != null) {
        table[key] = value;
        return;
      }
      h = metatable(table, "__newindex");
      if (h == null) {
        table[key] = value;
        return;
      }
    } else {
      h = metatable(table, "__newindex");
      if (h == null) {
        throw error("cannot set $table[$key] to $value");
      }
    }
    if (h is Fun) {
      call(h, [table, key, value]);
      return;
    }
    newindexEvent(h, key, value);
  }

  /// Calls a value (see §2.8).
  static List<dynamic> callEvent(dynamic func, dynamic args) {
    if (func is Fun) {
      return func(args as List<dynamic>);
    }
    var h = metatable(func, "__call");
    if (h != null) {
      return call(h, [func, args]);
    }
    throw error("cannot call $func");
  }

  /// Helper to perform the lookup of an unary operation.
  static dynamic performUnEvent(dynamic op, dynamic event, dynamic operation) {
    var h = metatable(op, event);
    if (h != null) {
      return call1(h, [op]);
    }
    throw error("cannot apply $operation to $op");
  }

  /// Helper to perform the lookup of a binary operation.
  static dynamic performBinEvent(dynamic op1, dynamic op2, String event, dynamic operation) {
    var h = getbinhandler(op1, op2, event);
    if (h != null) {
      return call1(h, [op1, op2]);
    }
    throw error("cannot $operation $op1 and $op2");
  }

  /// Returns the handler of the given [event] from either the [op1] value's metatable or the [op2] value's
  /// metatable. Returns [null] if neither [op1] nor [op2] have a metatable and/or such a handler.
  static Table? getbinhandler(dynamic op1, dynamic op2, String event) {
    return metatable(op1, event) ?? metatable(op2, event);
  }

  /// Returns the handler of the given [event] from [op1] and [op2] which must be of the same type and share the same
  /// handler. Returns [null] if this is not the case and therefore [op1] and [op2] aren't comparable.
  static Table? getequalhandler(dynamic op1, dynamic op2, String event) {
    if (type(op1) != type(op2)) {
      return null;
    }
    var h1 = metatable(op1, event);
    var h2 = metatable(op2, event);
    if (h1 == h2) {
      return h1;
    }
    return null;
  }

  /// Returns the given event handler from the value's metatable.
  /// Returns [null] if there is no metatable or no such handler in the metatable.
  static Table? metatable(dynamic value, dynamic event) {
    var mt = getmetatable(value);
    return mt != null
        ? mt[event] is Table
            ? mt[event] as Table
            : null
        : null;
  }

  /// Returns the metatable of the given [value].
  /// Returns [null] is there is no metatable.
  static Table? getmetatable(dynamic value) {
    if (value is num) return numMetatable;
    if (value is bool) return boolMetatable;
    if (value is String) return stringMetatable;
    if (value is Fun) return functionMetatable;
    if (value is Table) return value.metatable;
    return null;
  }

  /// Applies [func] with the given arguments and returns the result of the evaluation,
  /// reduced to a single value, dropping all additional values. Returns [null] if the
  /// function returned no result. Raises an error if [func] isn't a Function. [args]
  /// must be a List of values.
  static dynamic call1(dynamic func, List<dynamic> args) {
    if (func is Fun) {
      var result = func(args);
      return result.isNotEmpty ? result[0] : null;
    }
    throw error("cannot call $func");
  }

  /// Applies [func] with the given arguments and returns the result of the evaluation.
  /// Raises an error if [func] isn't a Function. [args] must be a List of values.
  static List<dynamic> call(dynamic func, List<dynamic> args) {
    if (func is Fun) {
      return func(args);
    }
    if (func is Function_) {
      return func.call(args);
    }
    throw error("cannot call $func");
  }

  /// Raises an error.
  static Exception error(String message) {
    throw Exception(message);
  }

  static final Table numMetatable = Table();
  static final Table boolMetatable = Table();
  static final Table stringMetatable = Table();
  static final Table functionMetatable = Table();

  /// Returns the type of the given [value] (see §5.1).
  static String type(dynamic value) {
    if (value is num) return "number";
    if (value is bool) return "boolean";
    if (value is String) return "string";
    if (value is Fun) return "function";
    if (value is Table) return "table";
    if (value == null) return "nil";
    return "userdata";
  }
}

/// Signals returning values from a user defined function.
/// See [Function.call] and [Return.eval].
class ReturnException {
  final List<dynamic> args;

  ReturnException(this.args);
}

/// Signals breaking a `while`, `repeat` or `for` loop.
/// See [While.eval], [Repeat.eval], [NumericFor.eval], [GenericFor.eval] and [Break.eval].
class BreakException {}

// --------------------------------------------------------------------------------------------------------------------
// AST
// --------------------------------------------------------------------------------------------------------------------

/// Something the environment can evaluate by calling [eval].
abstract class Node {
  dynamic eval(Env env);
}

/// A statement, evaluated for its side effect, returns nothing.
abstract class Stat extends Node {
  @override
  void eval(Env env);
}

/// A sequence of statements, evaluated sequentially for their side effects, returns nothing.
/// @see §3.3.1, §3.3.2
class Block extends Stat {
  final List<Node> stats;

  Block(this.stats);

  @override
  void eval(Env env) => stats.forEach((stat) => env.eval(stat));
}

/// A `while do` loop statement, can be stopped with `break`.
/// @see §3.3.4
class While extends Stat {
  final Exp exp;
  final Block block;

  While(this.exp, this.block);

  @override
  dynamic eval(Env env) {
    while (env.isTrue(env.eval(exp))) {
      try {
        env.eval(block);
      } on BreakException {
        break;
      }
    }
  }
}

/// A `repeat until` loop statement, can be stopped with `break`.
/// @see §3.3.4
class Repeat extends Stat {
  final Exp exp;
  final Block block;

  Repeat(this.exp, this.block);

  @override
  dynamic eval(Env env) {
    do {
      try {
        env.eval(block);
      } on BreakException {
        break;
      }
    } while (!env.isTrue(env.eval(exp)));
  }
}

/// An `if then else` conditional statement.
/// @see §3.3.4
class If extends Stat {
  final Exp exp;
  final Block thenBlock, elseBlock;

  If(this.exp, this.thenBlock, this.elseBlock);

  @override
  dynamic eval(Env env) => env.eval(env.isTrue(env.eval(exp)) ? thenBlock : elseBlock);
}

/// A numeric `for` loop statement, can be stopped with `break`.
/// It's an error if the three arguments don't evaluate to numbers.
/// @see §3.3.5
class NumericFor extends Stat {
  final String name;
  final Exp start, stop, step;
  final Block block;

  NumericFor(this.name, this.start, this.stop, this.step, this.block);

  @override
  void eval(Env env) async {
    var sta = env.eval(start);
    var sto = env.eval(stop);
    var ste = env.eval(step);
    if (sta is! num || sto is! num || ste is! num) throw "runtime error";
    var i = sta;
    while ((ste > 0 && i <= sto) || (ste <= 0 && i >= sto)) {
      var newEnv = Env(env);
      newEnv.bind(name, sta);
      try {
        newEnv.eval(block);
      } on BreakException {
        break;
      }
      i += ste;
    }
  }
}

/// A generic `for` loop statement, can be stopped with `break`.
/// @see §3.3.5.
class GenericFor extends Stat {
  final List<String> names;
  final List<Exp> exps;
  final Block block;

  GenericFor(this.names, this.exps, this.block);

  @override
  dynamic eval(Env env) {
    return Block([
      Local(["f", "s", "v"], exps),
      While(
          Lit(true),
          Block([
            Local(names, [
              FuncCall(Var("f"), [Var("s"), Var("v")])
            ]),
            If(Eq(Var(names[0]), Lit(null)), Block([Break()]), Block([])),
            Assign([Var("v")], [Var(names[0])]),
            ...block.stats,
          ]))
    ]).eval(env);
  }
}

/// Function definition (see §3.4.10).
/// Actually, this isn't strictly needed.
class FuncDef extends Stat {
  final List<String> names;
  final List<String> params;
  final Block block;

  FuncDef(this.names, this.params, this.block);

  @override
  void eval(Env env) {
    if (names.length == 1) {
      // TODO must create a global variable
      env.bind(names[0], Func(params, block).eval(env));
    } else {
      var v = Var(names[0]).eval(env);
      for (var i = 1; i < names.length - 1; i++) {
        v = Env.indexEvent(v, names[i]);
      }
      Env.newindexEvent(v, names[names.length - 1], Func(params, block).eval(env));
    }
  }
}

/// Method definition (see §3.4.10).
/// Actually, this isn't strictly needed.
class MethDef extends Stat {
  final List<String> names;
  final String method;
  final List<String> params;
  final Block block;

  MethDef(this.names, this.method, this.params, this.block);

  @override
  void eval(Env env) {
    var n = List.of(names);
    n.add(method);
    var p = List.of(params);
    p.insert(0, "self");
    FuncDef(n, p, block).eval(env);
  }
}

/// Local function definition (see §3.4.10).
/// Actually, this isn't strictly needed.
class LocalFuncDef extends Stat {
  final String name;
  final List<String> params;
  final Block block;

  LocalFuncDef(this.name, this.params, this.block);

  @override
  void eval(Env env) {
    env.bind(name, null);
    env.update(name, Func(params, block).eval(env));
  }
}

/// Defines and optionally initializes local variables (see §3.3.7).
class Local extends Stat {
  final List<String> names;
  final List<Exp> exps;

  Local(this.names, this.exps);

  @override
  void eval(Env env) {
    var vals = env.evalToList(exps);
    for (var i = 0; i < names.length; i++) {
      env.bind(names[i], i < vals.length ? vals[i] : null);
    }
  }
}

/// A `return` statement.
/// @see 3.3.4
class Return extends Stat {
  final List<Exp> exps;

  Return(this.exps);

  @override
  void eval(Env env) => throw ReturnException(env.evalToList(exps));
}

/// A `break` statement.
/// @see 3.3.4
class Break extends Stat {
  @override
  void eval(Env env) => throw BreakException();
}

/// Assigment of multiple values.
/// @see §3.3.3.
class Assign extends Stat {
  final List<Exp> vars;
  final List<Exp> exps;

  Assign(this.vars, this.exps);

  @override
  void eval(Env env) {
    var vals = env.evalToList(exps);
    for (var i = 0; i < vars.length; i++) {
      vars[i].set(env, i < vals.length ? vals[i] : null);
    }
  }
}

/// An expression computing a value.
abstract class Exp extends Node {
  void set(Env env, dynamic value) {
    throw "syntax error";
  }
}

/// A binary operation, only existing so that I don't have to declare [left] and [right] in every subclass.
abstract class Bin extends Exp {
  final Exp left, right;

  Bin(this.left, this.right);
}

/// Either the first value if not "false" and the second value isn't evaluated or the the second one.
class Or extends Bin {
  Or(Exp left, Exp right) : super(left, right);

  @override
  dynamic eval(Env env) {
    var v = env.eval(left);
    if (!env.isTrue(v)) {
      v = env.eval(right);
    }
    return v;
  }
}

/// Either the first value if "false" and the second value isn't evaluated or the second one.
class And extends Bin {
  And(Exp left, Exp right) : super(left, right);

  @override
  dynamic eval(Env env) {
    var v = env.eval(left);
    if (env.isTrue(v)) {
      v = env.eval(right);
    }
    return v;
  }
}

/// The `<` operation.
class Lt extends Bin {
  Lt(Exp left, Exp right) : super(left, right);

  @override
  dynamic eval(Env env) => Env.ltEvent(env.eval(left), env.eval(right));
}

/// The `>` operation (implemented as `not <=`).
class Gt extends Bin {
  Gt(Exp left, Exp right) : super(left, right);

  @override
  dynamic eval(Env env) => !Env.leEvent(env.eval(left), env.eval(right));
}

/// The `<=` operation.
class Le extends Bin {
  Le(Exp left, Exp right) : super(left, right);

  @override
  dynamic eval(Env env) => Env.leEvent(env.eval(left), env.eval(right));
}

/// The `>=` operation (implemented as `not <`).
class Ge extends Bin {
  Ge(Exp left, Exp right) : super(left, right);

  @override
  dynamic eval(Env env) => !Env.ltEvent(env.eval(left), env.eval(right));
}

/// The `~=` operation (implemented as `not ==`).
class Ne extends Bin {
  Ne(Exp left, Exp right) : super(left, right);

  @override
  dynamic eval(Env env) => !Env.eqEvent(env.eval(left), env.eval(right));
}

/// The `==` operation.
class Eq extends Bin {
  Eq(Exp left, Exp right) : super(left, right);

  @override
  dynamic eval(Env env) => Env.eqEvent(env.eval(left), env.eval(right));
}

/// The `..` operation.
class Concat extends Bin {
  Concat(Exp left, Exp right) : super(left, right);

  @override
  dynamic eval(Env env) => Env.concatEvent(env.eval(left), env.eval(right));
}

/// The `+` operation.
class Add extends Bin {
  Add(Exp left, Exp right) : super(left, right);

  @override
  dynamic eval(Env env) => Env.addEvent(env.eval(left), env.eval(right));
}

/// The `-` operation.
class Sub extends Bin {
  Sub(Exp left, Exp right) : super(left, right);

  @override
  dynamic eval(Env env) => Env.subEvent(env.eval(left), env.eval(right));
}

/// The `*` operation.
class Mul extends Bin {
  Mul(Exp left, Exp right) : super(left, right);

  @override
  dynamic eval(Env env) => Env.mulEvent(env.eval(left), env.eval(right));
}

/// The `/` operation.
class Div extends Bin {
  Div(Exp left, Exp right) : super(left, right);

  @override
  dynamic eval(Env env) => Env.divEvent(env.eval(left), env.eval(right));
}

/// The `%` operation.
class Mod extends Bin {
  Mod(Exp left, Exp right) : super(left, right);

  @override
  dynamic eval(Env env) => Env.modEvent(env.eval(left), env.eval(right));
}

/// The `not` operation.
class Not extends Exp {
  final Exp exp;

  Not(this.exp);

  @override
  dynamic eval(Env env) => !(env.eval(exp) as bool);
}

/// The unary `-` operation.
class Neg extends Exp {
  final Exp exp;

  Neg(this.exp);

  @override
  dynamic eval(Env env) => Env.unmEvent(env.eval(exp));
}

/// The unary `#` operation (length of strings and tables).
class Len extends Exp {
  final Exp exp;

  Len(this.exp);

  @override
  dynamic eval(Env env) => Env.lenEvent(env.eval(exp));
}

/// The `^` operation (power).
class Pow extends Bin {
  Pow(Exp left, Exp right) : super(left, right);

  @override
  dynamic eval(Env env) => Env.powEvent(env.eval(left), env.eval(right));
}

/// A literal value, i.e. `nil`, `true`, `false`, a number or a string.
class Lit extends Exp {
  final dynamic value;

  Lit(this.value);

  @override
  dynamic eval(Env env) => value;
}

/// A variable reference.
class Var extends Exp {
  final String name;

  Var(this.name);

  @override
  dynamic eval(Env env) => env.lookup(name);

  @override
  void set(Env env, dynamic value) => env.update(name, value);
}

/// The `[ ]` postfix operation.
class Index extends Exp {
  final Exp table, key;

  Index(this.table, this.key);

  @override
  dynamic eval(Env env) => Env.indexEvent(env.eval(table), env.eval(key));

  @override
  void set(Env env, dynamic value) => Env.newindexEvent(env.eval(table), env.eval(key), value);
}

/// Represents something that can be called and will return a list of arguments.
abstract class Call extends Exp {
  List<dynamic> evalList(Env env);

  @override
  dynamic eval(Env env) {
    var result = evalList(env);
    return result.isNotEmpty ? result[0] : null;
  }
}

/// Calling a method.
class MethCall extends Call {
  final Exp receiver;
  final String method;
  final List<Exp> args;

  MethCall(this.receiver, this.method, this.args);

  @override
  List<dynamic> evalList(Env env) {
    var r = env.eval(receiver);
    var f = Env.indexEvent(r, method);
    return Env.call(f, [r, ...env.evalToList(args)]);
  }
}

/// Calling a function.
class FuncCall extends Call {
  final Exp func;
  final List<Exp> args;

  FuncCall(this.func, this.args);

  @override
  List<dynamic> evalList(Env env) => Env.call(env.eval(func), env.evalToList(args));
}

/// Defining a function literal bound to the current environment.
class Func extends Exp {
  final List<String> params;
  final Block block;

  Func(this.params, this.block);

  @override
  dynamic eval(Env env) => Function_(env, params, block);
}

/// Creating a table. See [Field].
class TableConst extends Exp {
  final List<Field> fields;

  TableConst(this.fields);

  @override
  dynamic eval(Env env) {
    var t = Table();
    fields.forEach((field) => field.addTo(t, env));
    return t;
  }
}

/// Private class to represent a table field.
/// See [Table].
class Field {
  final Exp? key;
  final Exp value;

  Field(this.key, this.value);

  void addTo(Table table, Env env) {
    if (key == null) {
      table[table.length + 1] = env.eval(value);
    } else {
      table[env.eval(key!)] = env.eval(value);
    }
  }
}

// --------------------------------------------------------------------------------------------------------------------
// Scanner
// --------------------------------------------------------------------------------------------------------------------

/// The scanner breaks the source string into tokens using a fancy regular expression.
/// Some tokens have an associated value. The empty token represents the end of input.
class Scanner {
  final Iterator<Match> matches;
  Object? value;
  late String token;

  Scanner(String source)
      : matches = RegExp("\\s*(?:([-+*/%^#(){}\\[\\];:,]|[<>=]=?|~=|\\.{1,3})|(\\d+(?:\\.\\d+)?)|"
                "(\\w+)|('(?:\\\\.|[^'])*'|\"(?:\\\\.|[^\"])*\"))")
            .allMatches(source)
            .iterator {
    advance();
  }

  void advance() {
    token = nextToken();
  }

  String nextToken() {
    if (matches.moveNext()) {
      var match = matches.current;
      if (match.group(1) != null) {
        value = match.group(1);
        return value as String;
      }
      if (match.group(2) != null) {
        value = double.parse(match.group(2)!);
        return "Number";
      }
      if (match.group(3) != null) {
        value = match.group(3);
        return KEYWORDS.contains(value) ? value as String : "Name";
      }
      value = unescape(match.group(4)!.substring(1, match.group(4)!.length - 1));
      return "String";
    }
    return "";
  }

  static String unescape(String s) {
    return s.replaceAllMapped(RegExp("\\\\(u....|.)"), (Match m) {
      var c = m.group(1)!;
      if (c == 'b') return '\b';
      if (c == 'f') return '\f';
      if (c == 'n') return '\n';
      if (c == 'r') return '\r';
      if (c == 't') return '\t';
      if (c[0] == 'u') return String.fromCharCode(int.parse(c.substring(1), radix: 16));
      return c;
    });
  }

  static final Set<String> KEYWORDS = Set.of(
      "and break do else elseif end false for function if in local nil not or repeat return then true until while"
          .split(" "));
}

// --------------------------------------------------------------------------------------------------------------------
// Parser
// --------------------------------------------------------------------------------------------------------------------

/// The parser combines tokens from a [Scanner] into AST nodes ([Block], [Stat] and [Exp]).
class Parser {
  final Scanner scanner;

  Parser(this.scanner);

  // helpers

  Object? value() {
    var v = scanner.value;
    scanner.advance();
    return v;
  }

  bool peek(String token) => scanner.token == token;
  bool at(String token) {
    if (peek(token)) {
      scanner.advance();
      return true;
    }
    return false;
  }

  void expect(String token) {
    if (!at(token)) throw error("expected " + token);
  }

  bool isEnd() => ["", "else", "elseif", "end", "until"].any(peek);
  void end() => expect("end");
  Exception error(String message) => Exception("syntax error: $message");

  // grammar

  /// Parses a `chunk` resp. `block` according to
  ///
  ///     chunk = {stat [";"]} [laststat [";"]]
  ///     block = chunk
  ///
  /// TODO ";" is currently required, no distinction of `laststat`
  Block block() {
    var nodes = <Node>[];
    if (!isEnd()) {
      nodes.add(stat());
      while (at(";")) {
        nodes.add(stat());
      }
    }
    return Block(nodes);
  }

  /// Parses a `stat` or `laststat` according to
  ///
  ///     stat = varlist "=" explist |
  ///       funcall |
  ///       "do" block "end" |
  ///       "while" exp "do" block "end" |
  ///       "repeat" block "until" exp |
  ///       "if" exp "then" block {"elseif" exp "then" block} ["else" block] "end" |
  ///       "for" Name "=" exp "," exp ["," exp] "do" block "end" |
  ///       "for namelist "in" explist "do" block "end" |
  ///       "function" Name {"." Name} [":" Name] funcbody |
  ///       "local" "function" Name funcbody |
  ///       "local" namelist "=" explist
  ///     laststat = "return" [explist] | "break"
  Node stat() {
    if (at("do")) return statDo();
    if (at("while")) return statWhile();
    if (at("repeat")) return statRepeat();
    if (at("if")) return statIf();
    if (at("for")) return statFor();
    if (at("function")) return statFunction();
    if (at("local")) return statLocal();
    if (at("return")) return statReturn();
    if (at("break")) return statBreak();
    if (at(";")) return stat(); // ignore empty statements

    var e = exp();
    if (e is Var || e is Index) {
      // it must be the start of a varlist and therefore an assignment
      var v = varlist(e);
      expect("=");
      return Assign(v, explist());
    }
    // it must be `funcall`
    if (e is FuncCall || e is MethCall) {
      return e;
    }
    // if not, it's an error
    throw error("do, while, repeat, if, for, function, local, function call or assignment expected");
  }

  /// Parses a `stat` according to
  ///
  ///     stat = "do" block "end"
  Node statDo() {
    var b = block();
    end();
    return b;
  }

  /// Parses a `stat` according to
  ///
  ///     stat = "while" exp "do" block "end"
  Node statWhile() {
    var e = exp();
    expect("do");
    var b = block();
    end();
    return While(e, b);
  }

  /// Parses a `stat` according to
  ///
  ///     stat = "repeat" block "until" exp
  Node statRepeat() {
    var b = block();
    expect("until");
    var e = exp();
    return Repeat(e, b);
  }

  /// Parses a `stat` according to
  ///
  ///     stat = "if" exp "then" block {"elseif" exp "then" block} ["else" block] "end"
  Node statIf() {
    var e = exp();
    expect("then");
    Block b1 = block(), b2;
    if (at("elseif")) {
      b2 = Block([statIf()]);
    } else if (at("else")) {
      b2 = block();
    } else {
      b2 = Block([]);
    }
    end();
    return If(e, b1, b2);
  }

  /// Parses a `stat` according to
  ///
  ///     stat = "for" Name "=" exp "," exp ["," exp] "do" block "end" |
  ///            "for namelist "in" explist "do" block "end"
  Node statFor() {
    var n = namelist();
    if (at("=")) {
      if (n.length != 1) throw error("only one name before = allowed");
      var e1 = exp();
      expect(",");
      var e2 = exp();
      var e3 = at(",") ? exp() : Lit(1);
      expect("do");
      var b = block();
      end();
      return NumericFor(n[0], e1, e2, e3, b);
    }
    expect("in");
    var e = explist();
    expect("do");
    var b = block();
    end();
    return GenericFor(n, e, b);
  }

  /// Parses a `stat` according to
  ///
  ///     stat = "function" Name {"." Name} [":" Name] funcbody
  ///     funcbody = parlist body "end"
  Node statFunction() {
    var n = funcname();
    var m = at(":") ? name() : null;
    var p = parlist();
    var b = block();
    end();
    if (m != null) {
      return MethDef(n, m, p, b);
    }
    return FuncDef(n, p, b);
  }

  /// Returns a dot-separated sequence of names.
  List<String> funcname() => _namelist(".");

  /// Returns a comma-separated sequence of names
  List<String> namelist() => _namelist(",");

  List<String> _namelist(String t) {
    var names = <String>[];
    names.add(name());
    while (at(t)) {
      names.add(name());
    }
    return names;
  }

  /// Parses a `Name` or raises a syntax error.
  String name() => peek("Name") ? value() as String : throw error("Name expected");

  /// Parses a `stat` according to
  ///
  ///     stat = "local" "function" Name funcbody |
  ///            "local" namelist "=" explist
  ///     funcbody = "(" parlist ")" body "end"
  Node statLocal() {
    if (at("function")) {
      var n = name();
      var p = parlist();
      var b = block();
      end();
      return LocalFuncDef(n, p, b);
    }
    var n = namelist();
    var e = at("=") ? explist() : const <Exp>[];
    return Local(n, e);
  }

  /// Parses a `stat` according to
  ///
  ///     laststat = "return" [explist]
  Node statReturn() => Return(isEnd() ? [] : explist());

  /// Parses a `stat` according to
  ///
  ///     laststat = "break"
  Node statBreak() => Break();

  /// Parses a `parlist` according to
  ///
  ///     parlist = "(" [Name {"," Name}] ["," "..."] ")"
  List<String> parlist() {
    var params = <String>[];
    expect("(");
    if (!peek(")")) {
      while (peek("Name")) {
        params.add(name());
        if (!peek(")")) {
          expect(",");
        }
      }
      if (at("...")) {
        params.add("...");
      }
    }
    expect(")");
    return params;
  }

  /// Parses an expression according to
  ///
  ///     exp = "nil" | "false" | "true" | Number | String | "..." |
  ///       function | prefixexp | tableconstructor | exp binop exp |
  ///       unop exp
  ///     function = "function" funcbody
  ///     funcbody = "(" [parlist] ")" block "end"
  ///     parlist = namelist ["," "..."] | "..."
  ///     prefixexp = var | funcall | "(" exp ")"
  ///     funcall = prefixexp [":" Name] args
  ///     tableconstructor = { [fieldlist] }
  ///     fieldlist = field {fieldsep field} [fieldsep]
  ///     field = "[" exp "]" "=" exp | Name "=" exp | exp
  ///     fieldsep = "," | ";"
  ///     binop = "+" | "-" | "*" | "/" | "^" | "%" | ".." | "<" | "<=" |
  ///       ">" | ">=" | "==" | "~=" | "and" | "or"
  ///     unop = "-" | "not" | "#"
  Exp exp() {
    var e = expAnd();
    while (at("or")) {
      e = Or(e, expAnd());
    }
    return e;
  }

  Exp expAnd() {
    var e = expCmp();
    while (at("and")) {
      e = And(e, expCmp());
    }
    return e;
  }

  Exp expCmp() {
    var e = expConcat();
    while (["<", ">", "<=", "=>", "~=", "=="].any(peek)) {
      if (at("<")) {
        e = Lt(e, expConcat());
      } else if (at(">")) {
        e = Gt(e, expConcat());
      } else if (at("<=")) {
        e = Le(e, expConcat());
      } else if (at(">=")) {
        e = Ge(e, expConcat());
      } else if (at("~=")) {
        e = Ne(e, expConcat());
      } else if (at("==")) e = Eq(e, expConcat());
    }
    return e;
  }

  Exp expConcat() {
    var e = expAdd();
    while (at("..")) {
      e = Concat(e, expAdd());
    }
    return e;
  }

  Exp expAdd() {
    var e = expMul();
    while (peek("+") || peek("-")) {
      if (at("+")) {
        e = Add(e, expMul());
      } else if (at("-")) e = Sub(e, expMul());
    }
    return e;
  }

  Exp expMul() {
    var e = expUn();
    while (peek("*") || peek("/") || peek("%")) {
      if (at("*")) {
        e = Mul(e, expUn());
      } else if (at("/")) {
        e = Div(e, expUn());
      } else if (at("%")) e = Mod(e, expUn());
    }
    return e;
  }

  Exp expUn() {
    if (at("not")) {
      return Not(expUn());
    }
    if (at("#")) {
      return Len(expUn());
    }
    if (at("-")) {
      return Neg(expUn());
    }
    return expPow();
  }

  Exp expPow() {
    var e = expPrim();
    while (at("^")) {
      e = Pow(e, expPow());
    }
    return e;
  }

  Exp expPrim() {
    if (at("nil")) return Lit(null);
    if (at("true")) return Lit(true);
    if (at("false")) return Lit(false);
    if (peek("Number")) return Lit(value());
    if (peek("String")) return Lit(value());
    if (peek("...")) return Var(value() as String);
    if (at("function")) {
      var p = parlist(), b = block();
      end();
      return Func(p, b);
    }
    if (at("{")) return tableConstructor();
    if (peek("Name")) return expPostfix(Var(name()));
    if (at("(")) {
      var e = exp();
      expect(")");
      return expPostfix(e);
    }
    throw error("unexpected token");
  }

  Exp expPostfix(Exp p) {
    bool isCall() => peek("(") || peek("{") || peek("String");

    if (at("[")) {
      var k = exp();
      expect("]");
      return expPostfix(Index(p, k));
    }
    if (at(".")) {
      var k = Lit(name());
      return expPostfix(Index(p, k));
    }
    if (at(":")) {
      var n = name();
      if (!isCall()) throw error("no args after method call");
      return expPostfix(MethCall(p, n, args()));
    }
    if (isCall()) {
      return expPostfix(FuncCall(p, args()));
    }
    return p;
  }

  /// Parses a list of arguments according to
  ///
  ///     args = ( [explist] ) | tableconstructor | String
  List<Exp> args() {
    if (peek("String")) return [Lit(value())];
    if (at("{")) return [tableConstructor()];
    if (at("(")) {
      var e = peek(")") ? <Exp>[] : explist();
      expect(")");
      return e;
    }
    throw error("invalid args");
  }

  /// Parses a list of expressions according to
  ///
  ///     explist = exp {"," exp}
  List<Exp> explist() {
    var nodes = <Exp>[];
    nodes.add(exp());
    while (at(",")) {
      nodes.add(exp());
    }
    return nodes;
  }

  /// Parses a `tableconstructor` according to
  ///
  ///     tableconstructor = { [fieldlist] }
  ///     fieldlist = field {fieldsep field} [fieldsep]
  ///     fieldsep = "," | ";"
  Exp tableConstructor() {
    var fields = <Field>[];
    while (!at("}")) {
      fields.add(field());
      if (!peek("}")) expect(peek(";") ? ";" : ",");
    }
    return TableConst(fields);
  }

  /// Parses a `field` of `tableconstructor` according to
  ///
  ///     field = "[" exp "]" "=" exp | Name "=" exp | exp
  Field field() {
    if (at("[")) {
      var k = exp();
      expect("]");
      expect("=");
      return Field(k, exp());
    }
    var e = exp();
    if (e is Var) {
      expect("=");
      return Field(Lit(e.name), exp());
    }
    return Field(null, e);
  }

  /// Parses a list of expressions that may occur on the left hand side
  /// of an assignment and returns a list of such expressions.
  ///
  ///     varlist = var {"," var}
  List<Exp> varlist(Exp e) {
    var exps = <Exp>[e];
    while (at(",")) {
      exps.add(var_());
    }
    return exps;
  }

  /// Parses an exp that may occur on the left hand side of an assignment.
  ///
  ///     var = Name | prefixexp "[" exp "]" | prefixexp "." Name
  Exp var_() {
    var e = exp();
    if (e is Var || e is Index) return e;
    throw error("expression must not occur on left hand side");
  }
}
