// Copyright 2013, 2020 Stefan Matthias Aust. Licensed under MIT (http://opensource.org/licenses/MIT)
import "dart:math" show pow;

/*
 * This is a parser and runtime system for Lua 5.1 which lacks most if not 
 * all of the Lua standard library. I created the parser a couple of years 
 * ago and now ported it to Dart just to see how difficult it would be.
 *  -sma, 2013
 */

void main() {
  var env = Env(null);
  env.bind("print", (List<Object> args) {
    print(Env.printString(args[0]));
    return <Object>[]; 
  });
  Parser(Scanner("print('hello')")).block().exec(env);
  Parser(Scanner("print(3 + 4)")).block().exec(env);
  Parser(Scanner("for i = 0, 5 do print(i) end")).block().exec(env);
  Parser(Scanner("function fac(n) if n == 0 then return 1 end; return n * fac(n - 1) end; print(fac(6))")).block().exec(env);
  Parser(Scanner("print({}); print({1, 2}); print({a=1, ['b']=2})")).block().exec(env);
  Parser(Scanner("print(#{1, [2]=2, [4]=4, n=5})")).block().exec(env);
  Parser(Scanner("local a, b = 3, 4; a, b = b, a; print(a..'&'..b)")).block().exec(env);
  Parser(Scanner("function v(a, ...) return ... end; print(v(1, 2, 3))")).block().exec(env);
  Parser(Scanner("function v() return 1, 2 end; local a, b = v(); print(b)")).block().exec(env);
  Parser(Scanner("function a(x,y) return x+y end; function b() return 3,4 end; print(a(b()))")).block().exec(env);
  Parser(Scanner("local c = {}; function c:m() return self.b end; print(c.m); c.b=42; print(c:m())")).block().exec(env);
}

// --------------------------------------------------------------------------------------------------------------------
// Runtime system
// --------------------------------------------------------------------------------------------------------------------

const nil = Object();

/// Tables are Lua's main datatype: an associative array with an optional
/// metatable describing the table's behavior. It can be used like and
/// array or like an dictionary a.k.a. hash map. It can also be used like
/// instances of classes.
final class Table {
  Table();
  Table.from(Iterable<Object> i) {
    var j = 1;
    i.forEach((e) => fields[j++] = e);
  }

  final fields = <Object, Object>{};
  Table? metatable;

  Object? operator [](Object k) => fields[k];
  void operator []=(Object k, Object v) => fields[k] = v;
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
/// The [call] method conforms to [Fun].
final class UserFunc {
  UserFunc(this.env, this.params, this.block);

  final Env env;
  final List<String> params;
  final Block block;

  List<Object> call(List<Object> args) {
    var newEnv = Env(env);

    // bind arguments to parameters
    params.asMap().forEach((index, name) {
      if (name == "...") {
        newEnv.bind(name, Table.from(args.sublist(index)));
      } else {
        newEnv.bind(name, index < args.length ? args[index] : nil);
      }
    });

    // execute body
    try {
      block.exec(newEnv);
    } on ReturnException catch (e) {
      return e.args;
    }
    return [];
  }

  @override
  String toString() => "<func>";
}

/// Common function type for built-in functions and user defined functions.
/// Notice that functions should always return a List of results.
typedef Fun = List<Object> Function(List<Object> args);

/// Environments are used to keep variable bindings and evaluate AST nodes.
final class Env {
  Env(this.parent);

  final Env? parent;
  final vars = <String, Object>{};

  // variables

  void bind(String name, Object value) {
    vars[name] = value;
  }

  void update(String name, Object value) {
    if (vars.containsKey(name)) {
      vars[name] = value;
    } else if (parent != null) {
      parent!.update(name, value);
    } else {
      throw "assignment to unknown variable $name";
    }
  }

  Object lookup(String name) {
    if (vars.containsKey(name)) {
      return vars[name]!;
    } else if (parent != null) {
      return parent!.lookup(name);
    }
    throw "reference of unknown variable $name";
  }

  Object eval(Exp node) => node.eval(this);

  List<Object> evalToList(List<Exp> exps) {
    if (exps.isNotEmpty) {
      var last = exps[exps.length - 1];
      if (last is Call) {
        return exps.sublist(0, exps.length - 1).map(eval).toList()..addAll(last.evalList(this));
      }
    }
    return exps.map(eval).toList();
  }

  bool isTrue(Object value) => value != nil && value != false;

  // built-in operations

  /// Adds two values (see §2.8).
  static Object addEvent(Object op1, Object op2) {
    if (op1 is num && op2 is num) {
      return op1 + op2;
    }
    return performBinEvent(op1, op2, "__add", "add");
  }

  /// Subtracts two values (see §2.8).
  static Object subEvent(Object op1, Object op2) {
    if (op1 is num && op2 is num) {
      return op1 - op2;
    }
    return performBinEvent(op1, op2, "__sub", "subtract");
  }

  /// Multiplies two values (see §2.8).
  static Object mulEvent(Object op1, Object op2) {
    if (op1 is num && op2 is num) {
      return op1 * op2;
    }
    return performBinEvent(op1, op2, "__mul", "multiply");
  }

  /// Divides two values (see §2.8).
  static Object divEvent(Object op1, Object op2) {
    if (op1 is num && op2 is num) {
      return op1 / op2;
    }
    return performBinEvent(op1, op2, "__div", "divide");
  }

  /// Applies "modulo" to two values (see §2.8).
  static Object modEvent(Object op1, Object op2) {
    if (op1 is num && op2 is num) {
      return op1 % op2;
    }
    return performBinEvent(op1, op2, "__mod", "modulo");
  }

  /// Applies "power" to two values (see §2.8).
  static Object powEvent(Object op1, Object op2) {
    if (op1 is num && op2 is num) {
      return pow(op1, op2);
    }
    return performBinEvent(op1, op2, "__pow", "power");
  }

  /// Applies unary minus (see §2.8).
  static Object unmEvent(Object op) {
    if (op is num) {
      return -op;
    }
    return performUnEvent(op, "__unm", "unary minus");
  }

  /// Concatenates two values (see §2.8).
  static Object concatEvent(Object op1, Object op2) {
    if ((op1 is num || op1 is String) && (op2 is num || op2 is String)) {
      return "${printString(op1)}${printString(op2)}";
    }
    return performBinEvent(op1, op2, "__concat", "concat");
  }

  /// Applies length (see §2.8).
  static Object lenEvent(Object op) {
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
  static bool eqEvent(Object op1, Object op2) {
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
  static bool ltEvent(Object op1, Object op2) {
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
  static bool leEvent(Object op1, Object op2) {
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
  static Object indexEvent(Object table, Object key) {
    Object? h;
    if (table is Table) {
      var v = table[key];
      if (v != null) {
        return v;
      }
      h = metatable(table, "__index");
      if (h == null) {
        return nil;
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
  static void newindexEvent(Object table, Object key, Object value) {
    Object? h;
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
  static List<Object> callEvent(Object func, Object args) {
    if (func is Fun) {
      return func(args as List<Object>);
    }
    var h = metatable(func, "__call");
    if (h != null) {
      return call(h, [func, args]);
    }
    throw error("cannot call $func");
  }

  /// Helper to perform the lookup of an unary operation.
  static Object performUnEvent(Object op, Object event, Object operation) {
    var h = metatable(op, event);
    if (h != null) {
      return call1(h, [op]);
    }
    throw error("cannot apply $operation to $op");
  }

  /// Helper to perform the lookup of a binary operation.
  static Object performBinEvent(Object op1, Object op2, String event, Object operation) {
    var h = getbinhandler(op1, op2, event);
    if (h != null) {
      return call1(h, [op1, op2]);
    }
    throw error("cannot $operation $op1 and $op2");
  }

  /// Returns the handler of the given [event] from either the [op1] value's metatable or the [op2] value's
  /// metatable. Returns `null` if neither [op1] nor [op2] have a metatable and/or such a handler.
  static Table? getbinhandler(Object op1, Object op2, String event) {
    return metatable(op1, event) ?? metatable(op2, event);
  }

  /// Returns the handler of the given [event] from [op1] and [op2] which must be of the same type and share the same
  /// handler. Returns `null` if this is not the case and therefore [op1] and [op2] aren't comparable.
  static Table? getequalhandler(Object op1, Object op2, String event) {
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
  /// Returns `null` if there is no metatable or no such handler in the metatable.
  static Table? metatable(Object value, Object event) {
    var mt = getmetatable(value);
    return mt != null
        ? mt[event] is Table
            ? mt[event] as Table
            : null
        : null;
  }

  /// Returns the metatable of the given [value].
  /// Returns `null` is there is no metatable.
  static Table? getmetatable(Object value) {
    if (value is num) return numMetatable;
    if (value is bool) return boolMetatable;
    if (value is String) return stringMetatable;
    if (value is Fun) return functionMetatable;
    if (value is Table) return value.metatable;
    return null;
  }

  /// Applies [func] with the given arguments and returns the result of the evaluation,
  /// reduced to a single value, dropping all additional values. Returns `null` if the
  /// function returned no result. Raises an error if [func] isn't a Function. [args]
  /// must be a List of values.
  static Object call1(Object func, List<Object> args) {
    if (func is Fun) {
      var result = func(args);
      return result.isNotEmpty ? result[0] : nil;
    }
    throw error("cannot call $func");
  }

  /// Applies [func] with the given arguments and returns the result of the evaluation.
  /// Raises an error if [func] isn't a Function. [args] must be a List of values.
  static List<Object> call(Object func, List<Object> args) {
    if (func is Fun) {
      return func(args);
    }
    if (func is UserFunc) {
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
  static String type(Object value) {
    if (value is num) return "number";
    if (value is bool) return "boolean";
    if (value is String) return "string";
    if (value is Fun) return "function";
    if (value is Table) return "table";
    if (value == nil) return "nil";
    return "userdata";
  }

  static String printString(Object value) {
    if (value == nil) return "nil";
    if (value is num) {
      if (value is double && value.floorToDouble() == value) {
        return value.floor().toString();
      }
    }
    return value.toString();
  }
}

/// Signals returning values from a user defined function.
/// See [UserFunc.call] and [Return.exec].
final class ReturnException {
  ReturnException(this.args);

  final List<Object> args;
}

/// Signals breaking a `while`, `repeat` or `for` loop.
/// See [While.exec], [Repeat.exec], [NumericFor.exec], [GenericFor.exec] and [Break.exec].
final class BreakException {}

// --------------------------------------------------------------------------------------------------------------------
// AST
// --------------------------------------------------------------------------------------------------------------------

/// A statement, evaluated for its side effect, returns nothing.
sealed class Stat {
  void exec(Env env);
}

/// A sequence of statements, evaluated sequentially for their side effects, returns nothing.
/// @see §3.3.1, §3.3.2
final class Block extends Stat {
  Block(this.stats);

  final List<Stat> stats;

  @override
  void exec(Env env) => stats.forEach((stat) => stat.exec(env));
}

/// A `while do` loop statement, can be stopped with `break`.
/// @see §3.3.4
final class While extends Stat {
  While(this.exp, this.block);

  final Exp exp;
  final Block block;

  @override
  void exec(Env env) {
    while (env.isTrue(env.eval(exp))) {
      try {
        block.exec(env);
      } on BreakException {
        break;
      }
    }
  }
}

/// A `repeat until` loop statement, can be stopped with `break`.
/// @see §3.3.4
final class Repeat extends Stat {
  Repeat(this.exp, this.block);

  final Exp exp;
  final Block block;

  @override
  void exec(Env env) {
    do {
      try {
        block.exec(env);
      } on BreakException {
        break;
      }
    } while (!env.isTrue(env.eval(exp)));
  }
}

/// An `if then else` conditional statement.
/// @see §3.3.4
final class If extends Stat {
  If(this.exp, this.thenBlock, this.elseBlock);

  final Exp exp;
  final Block thenBlock, elseBlock;

  @override
  void exec(Env env) => (env.isTrue(exp.eval(env)) ? thenBlock : elseBlock).exec(env);
}

/// A numeric `for` loop statement, can be stopped with `break`.
/// It's an error if the three arguments don't evaluate to numbers.
/// @see §3.3.5
final class NumericFor extends Stat {
  NumericFor(this.name, this.start, this.stop, this.step, this.block);

  final String name;
  final Exp start, stop, step;
  final Block block;

  @override
  void exec(Env env) {
    var sta = env.eval(start);
    var sto = env.eval(stop);
    var ste = env.eval(step);
    if (sta is! num || sto is! num || ste is! num) throw "runtime error";
    var i = sta;
    while ((ste > 0 && i <= sto) || (ste <= 0 && i >= sto)) {
      var newEnv = Env(env);
      newEnv.bind(name, i);
      try {
        block.exec(newEnv);
      } on BreakException {
        break;
      }
      i += ste;
    }
  }
}

/// A generic `for` loop statement, can be stopped with `break`.
/// @see §3.3.5.
final class GenericFor extends Stat {
  GenericFor(this.names, this.exps, this.block);

  final List<String> names;
  final List<Exp> exps;
  final Block block;

  @override
  void exec(Env env) {
    return Block([
      Local(["f", "s", "v"], exps),
      While(
        Lit(true),
        Block(
          [
            Local(names, [
              FuncCall(Var("f"), [Var("s"), Var("v")])
            ]),
            If(Eq(Var(names[0]), Lit(nil)), Block([Break()]), Block([])),
            Assign([Var("v")], [Var(names[0])]),
            ...block.stats,
          ],
        ),
      )
    ]).exec(env);
  }
}

/// Function definition (see §3.4.10).
/// Actually, this node isn't strictly needed.
final class FuncDef extends Stat {
  FuncDef(this.names, this.params, this.block);

  final List<String> names;
  final List<String> params;
  final Block block;

  @override
  void exec(Env env) {
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
/// Actually, this node isn't strictly needed.
final class MethDef extends Stat {
  MethDef(this.names, this.method, this.params, this.block);

  final List<String> names;
  final String method;
  final List<String> params;
  final Block block;

  @override
  void exec(Env env) {
    var n = List.of(names);
    n.add(method);
    var p = List.of(params);
    p.insert(0, "self");
    FuncDef(n, p, block).exec(env);
  }
}

/// Local function definition (see §3.4.10).
/// Actually, this node isn't strictly needed.
final class LocalFuncDef extends Stat {
  LocalFuncDef(this.name, this.params, this.block);

  final String name;
  final List<String> params;
  final Block block;

  @override
  void exec(Env env) {
    env.bind(name, nil);
    env.update(name, Func(params, block).eval(env));
  }
}

/// Defines and optionally initializes local variables (see §3.3.7).
final class Local extends Stat {
  Local(this.names, this.exps);

  final List<String> names;
  final List<Exp> exps;

  @override
  void exec(Env env) {
    var vals = env.evalToList(exps);
    for (var i = 0; i < names.length; i++) {
      env.bind(names[i], i < vals.length ? vals[i] : nil);
    }
  }
}

/// A `return` statement.
/// @see 3.3.4
final class Return extends Stat {
  Return(this.exps);

  final List<Exp> exps;

  @override
  void exec(Env env) => throw ReturnException(env.evalToList(exps));
}

/// A `break` statement.
/// @see 3.3.4
final class Break extends Stat {
  @override
  void exec(Env env) => throw BreakException();
}

/// Assigment of multiple values.
/// @see §3.3.3.
final class Assign extends Stat {
  Assign(this.vars, this.exps);

  final List<Exp> vars;
  final List<Exp> exps;

  @override
  void exec(Env env) {
    var vals = env.evalToList(exps);
    for (var i = 0; i < vars.length; i++) {
      vars[i].set(env, i < vals.length ? vals[i] : nil);
    }
  }
}

/// An expression computing a value.
abstract class Exp extends Stat {
  @override
  void exec(Env env) => eval(env);
  Object eval(Env env);
  void set(Env env, Object value) {
    throw "syntax error";
  }
}

/// A binary operation, only existing so that I don't have to declare [left] and [right] in every subclass.
abstract class Bin extends Exp {
  Bin(this.left, this.right);

  final Exp left;
  final Exp right;
}

/// Either the first value if not "false" and the second value isn't evaluated or the the second one.
final class Or extends Bin {
  Or(super.left, super.right);

  @override
  Object eval(Env env) {
    var v = env.eval(left);
    if (!env.isTrue(v)) {
      v = env.eval(right);
    }
    return v;
  }
}

/// Either the first value if "false" and the second value isn't evaluated or the second one.
final class And extends Bin {
  And(super.left, super.right);

  @override
  Object eval(Env env) {
    var v = env.eval(left);
    if (env.isTrue(v)) {
      v = env.eval(right);
    }
    return v;
  }
}

/// The `<` operation.
final class Lt extends Bin {
  Lt(super.left, super.right);

  @override
  Object eval(Env env) => Env.ltEvent(env.eval(left), env.eval(right));
}

/// The `>` operation (implemented as `not <=`).
final class Gt extends Bin {
  Gt(super.left, super.right);

  @override
  Object eval(Env env) => !Env.leEvent(env.eval(left), env.eval(right));
}

/// The `<=` operation.
final class Le extends Bin {
  Le(super.left, super.right);

  @override
  Object eval(Env env) => Env.leEvent(env.eval(left), env.eval(right));
}

/// The `>=` operation (implemented as `not <`).
final class Ge extends Bin {
  Ge(super.left, super.right);

  @override
  Object eval(Env env) => !Env.ltEvent(env.eval(left), env.eval(right));
}

/// The `~=` operation (implemented as `not ==`).
final class Ne extends Bin {
  Ne(super.left, super.right);

  @override
  Object eval(Env env) => !Env.eqEvent(env.eval(left), env.eval(right));
}

/// The `==` operation.
final class Eq extends Bin {
  Eq(super.left, super.right);

  @override
  Object eval(Env env) => Env.eqEvent(env.eval(left), env.eval(right));
}

/// The `..` operation.
final class Concat extends Bin {
  Concat(super.left, super.right);

  @override
  Object eval(Env env) => Env.concatEvent(env.eval(left), env.eval(right));
}

/// The `+` operation.
final class Add extends Bin {
  Add(super.left, super.right);

  @override
  Object eval(Env env) => Env.addEvent(env.eval(left), env.eval(right));
}

/// The `-` operation.
final class Sub extends Bin {
  Sub(super.left, super.right);

  @override
  Object eval(Env env) => Env.subEvent(env.eval(left), env.eval(right));
}

/// The `*` operation.
final class Mul extends Bin {
  Mul(super.left, super.right);

  @override
  Object eval(Env env) => Env.mulEvent(env.eval(left), env.eval(right));
}

/// The `/` operation.
final class Div extends Bin {
  Div(super.left, super.right);

  @override
  Object eval(Env env) => Env.divEvent(env.eval(left), env.eval(right));
}

/// The `%` operation.
final class Mod extends Bin {
  Mod(super.left, super.right);

  @override
  Object eval(Env env) => Env.modEvent(env.eval(left), env.eval(right));
}

/// The `not` operation.
final class Not extends Exp {
  Not(this.exp);

  final Exp exp;

  @override
  Object eval(Env env) => !(env.eval(exp) as bool);
}

/// The unary `-` operation.
final class Neg extends Exp {
  Neg(this.exp);

  final Exp exp;

  @override
  Object eval(Env env) => Env.unmEvent(env.eval(exp));
}

/// The unary `#` operation (length of strings and tables).
final class Len extends Exp {
  Len(this.exp);

  final Exp exp;

  @override
  Object eval(Env env) => Env.lenEvent(env.eval(exp));
}

/// The `^` operation (power).
final class Pow extends Bin {
  Pow(super.left, super.right);

  @override
  Object eval(Env env) => Env.powEvent(env.eval(left), env.eval(right));
}

/// A literal value, i.e. `nil`, `true`, `false`, a number or a string.
final class Lit extends Exp {
  Lit(this.value);

  final Object value;

  @override
  Object eval(Env env) => value;
}

/// A variable reference.
final class Var extends Exp {
  Var(this.name);

  final String name;

  @override
  Object eval(Env env) => env.lookup(name);

  @override
  void set(Env env, Object value) => env.update(name, value);
}

/// The `[ ]` postfix operation.
final class Index extends Exp {
  Index(this.table, this.key);

  final Exp table, key;

  @override
  Object eval(Env env) => Env.indexEvent(env.eval(table), env.eval(key));

  @override
  void set(Env env, Object value) => Env.newindexEvent(env.eval(table), env.eval(key), value);
}

/// Represents something that can be called and will return a list of arguments.
abstract class Call extends Exp {
  List<Object> evalList(Env env);

  @override
  Object eval(Env env) {
    var result = evalList(env);
    return result.isNotEmpty ? result[0] : nil;
  }
}

/// Calling a method.
final class MethCall extends Call {
  MethCall(this.receiver, this.method, this.args);

  final Exp receiver;
  final String method;
  final List<Exp> args;

  @override
  List<Object> evalList(Env env) {
    var r = env.eval(receiver);
    var f = Env.indexEvent(r, method);
    return Env.call(f, [r, ...env.evalToList(args)]);
  }
}

/// Calling a function.
final class FuncCall extends Call {
  FuncCall(this.func, this.args);

  final Exp func;
  final List<Exp> args;

  @override
  List<Object> evalList(Env env) => Env.call(env.eval(func), env.evalToList(args));
}

/// Defining a function literal bound to the current environment.
final class Func extends Exp {
  Func(this.params, this.block);

  final List<String> params;
  final Block block;

  @override
  Object eval(Env env) => UserFunc(env, params, block);
}

/// Creating a table. See [Field].
final class TableConst extends Exp {
  TableConst(this.fields);

  final List<Field> fields;

  @override
  Object eval(Env env) {
    var t = Table();
    fields.forEach((field) => field.addTo(t, env));
    return t;
  }
}

/// Private class to represent a table field.
/// See [Table].
final class Field {
  Field(this.key, this.value);

  final Exp? key;
  final Exp value;

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
final class Scanner {
  Scanner(String source)
      : matches = RegExp(
          "\\s*(?:"
          "(--\\[.*?--]|--[^\n]*\$)|"
          "(\\[\\[.*?]])|"
          "([-+*/%^#(){}\\[\\];:,]|[<>=]=?|~=|\\.{1,3})|"
          "(\\d+(?:\\.\\d+)?)|"
          "(\\w+)|"
          "('(?:\\\\.|[^'])*'|\"(?:\\\\.|[^\"])*\")|"
          "(.))",
          multiLine: true,
          dotAll: true,
        ).allMatches(_stripHash(source)).iterator {
    advance();
  }

  final Iterator<Match> matches;
  Object? value;
  late (String, int) token;

  static String _stripHash(String source) {
    if (source.startsWith("#")) {
      var index = source.indexOf("\n");
      return index != -1 ? source.substring(index + 1) : "";
    }
    return source;
  }

  void advance() {
    token = nextToken();
  }

  (String, int) nextToken() {
    if (matches.moveNext()) {
      var match = matches.current;
      if (match[0]!.trim().isEmpty) return ('', match.end);
      if (match[1] != null) return nextToken();
      if (match[3] != null) {
        value = match[3];
        return (value as String, match.start);
      }
      if (match[4] != null) {
        value = double.parse(match[4]!);
        return ("Number", match.start);
      }
      if (match[5] != null) {
        value = match[5];
        return (_keywords.contains(value) ? value as String : "Name", match.start);
      }
      var str1 = match[6];
      if (str1 != null) {
        value = unescape(str1.substring(1, str1.length - 1));
        return ("String", match.start);
      }
      var str2 = match[2];
      if (str2 != null) {
        value = unescape(str2.substring(2, str2.length - 2));
        return ("String", match.start);
      }
      return ("Error", match.start);
    }
    return ("", 0);
  }

  static String unescape(String s) {
    return s.replaceAllMapped(RegExp("\\\\(u....|.)"), (match) {
      var c = match[1]!;
      if (c == 'b') return '\b';
      if (c == 'f') return '\f';
      if (c == 'n') return '\n';
      if (c == 'r') return '\r';
      if (c == 't') return '\t';
      if (c[0] == 'u') return String.fromCharCode(int.parse(c.substring(1), radix: 16));
      return c;
    });
  }

  static final Set<String> _keywords = Set.of(
      "and break do else elseif end false for function if in local nil not or repeat return then true until while"
          .split(" "));
}

// --------------------------------------------------------------------------------------------------------------------
// Parser
// --------------------------------------------------------------------------------------------------------------------

/// The parser combines tokens from a [Scanner] into AST nodes ([Block], [Stat] and [Exp]).
final class Parser {
  Parser(this.scanner);

  final Scanner scanner;

  // helpers

  Object value() {
    var v = scanner.value!;
    scanner.advance();
    return v;
  }

  bool peek(String token) => scanner.token.$1 == token;
  bool at(String token) {
    if (peek(token)) {
      scanner.advance();
      return true;
    }
    return false;
  }

  void expect(String token) {
    if (!at(token)) throw error("expected $token");
  }

  bool isEnd() => ["", "else", "elseif", "end", "until"].any(peek);
  void end() => expect("end");
  Exception error(String message) => Exception("syntax error: $message at ${scanner.token.$2}");

  // grammar

  /// Parses a `chunk` resp. `block` according to
  ///
  ///     chunk = {stat [";"]} [laststat [";"]]
  ///     block = chunk
  ///
  /// TODO ";" is currently required, no distinction of `laststat`
  Block block() {
    var nodes = <Stat>[];
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
  Stat stat() {
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
  Stat statDo() {
    var b = block();
    end();
    return b;
  }

  /// Parses a `stat` according to
  ///
  ///     stat = "while" exp "do" block "end"
  Stat statWhile() {
    var e = exp();
    expect("do");
    var b = block();
    end();
    return While(e, b);
  }

  /// Parses a `stat` according to
  ///
  ///     stat = "repeat" block "until" exp
  Stat statRepeat() {
    var b = block();
    expect("until");
    var e = exp();
    return Repeat(e, b);
  }

  /// Parses a `stat` according to
  ///
  ///     stat = "if" exp "then" block {"elseif" exp "then" block} ["else" block] "end"
  Stat statIf() {
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
  Stat statFor() {
    var n = namelist();
    if (at("=")) {
      if (n.length != 1) throw error("only one name before = allowed");
      var e1 = exp();
      expect(",");
      var e2 = exp();
      var e3 = at(",") ? exp() : Lit(1.0);
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
  Stat statFunction() {
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
  Stat statLocal() {
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
  Stat statReturn() => Return(isEnd() ? [] : explist());

  /// Parses a `stat` according to
  ///
  ///     laststat = "break"
  Stat statBreak() => Break();

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
  /// ```
  /// exp = "nil" | "false" | "true" | Number | String | "..." |
  ///   function | prefixexp | tableconstructor | exp binop exp |
  ///   unop exp
  /// function = "function" funcbody
  /// funcbody = "(" [parlist] ")" block "end"
  /// parlist = namelist ["," "..."] | "..."
  /// prefixexp = var | funcall | "(" exp ")"
  /// funcall = prefixexp [":" Name] args
  /// tableconstructor = { [fieldlist] }
  /// fieldlist = field {fieldsep field} [fieldsep]
  /// field = "[" exp "]" "=" exp | Name "=" exp | exp
  /// fieldsep = "," | ";"
  /// binop = "+" | "-" | "*" | "/" | "^" | "%" | ".." | "<" | "<=" |
  ///   ">" | ">=" | "==" | "~=" | "and" | "or"
  /// unop = "-" | "not" | "#"
  /// ```
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
      } else if (at("==")) {
        e = Eq(e, expConcat());
      }
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
      } else if (at("-")) {
        e = Sub(e, expMul());
      }
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
      } else if (at("%")) {
        e = Mod(e, expUn());
      }
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
    if (at("nil")) return Lit(nil);
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
  /// ```
  /// tableconstructor = { [fieldlist] }
  /// fieldlist = field {fieldsep field} [fieldsep]
  /// fieldsep = "," | ";"
  /// ```
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
