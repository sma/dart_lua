import 'dart:convert';
import 'dart:io';

import 'lua.dart';

void main() {
  var c = 0, d = 0;
  for (final file in Directory('lua/tests').listSync().whereType<File>()) {
    if (['main', 'all', 'literals'].any(file.path.contains)) continue;
    print('${file.path}...');
    try {
      scan(file.readAsStringSync(encoding: latin1));
      parse(file.readAsStringSync(encoding: latin1));
      c++;
    } catch (e) {
      print(e);
    }
    d++;
  }
  print('$c/$d passed');
}

void scan(String source) {
  final scanner = Scanner(source);
  while (scanner.token.$1 != '') {
    if (scanner.token.$1 == 'Error') {
      throw 'invalid token at ${scanner.token.$2}';
    }
    scanner.advance();
  }
}

void parse(String source) {
  final parser = Parser(Scanner(source));
  while(parser.scanner.token.$1 != '') {
    parser.stat();
    // print(parser.stat().s);
  }
  if (!parser.at('')) {
    throw 'Expected end of input';
  }
}

extension on Stat {
  String get s => switch (this) {
        Block(:final stats) => stats.map((s) => s.s).join('; '),
        While(:final exp, :final block) => 'while ${exp.s} do ${block.s} end',
        Repeat(:final exp, :final block) => 'repeat ${block.s} until ${exp.s}',
        If(:final exp, :final thenBlock, :final elseBlock) => 'if ${exp.s} then ${thenBlock.s} else ${elseBlock.s} end',
        NumericFor(:final name, :final start, :final stop, :final step, :final block) =>
          'for $name = ${start.s}, ${stop.s}, ${step.s} do ${block.s} end',
        GenericFor(:final names, :final exps, :final block) =>
          'for ${names.join(', ')} in ${exps.s(', ')} do ${block.s} end',
        FuncDef(:final names, :final params, :final block) =>
          'function ${names.join(', ')}(${params.join(', ')}) ${block.s} end',
        MethDef(:final names, :final method, :final params, :final block) =>
          'function $method:${names.join(', ')}(${params.join(', ')}) ${block.s} end',
        LocalFuncDef(:final name, :final params, :final block) =>
          'local function $name(${params.join(', ')}) ${block.s} end',
        Local(:final names, :final exps) => 'local ${names.join(', ')} = ${exps.s(', ')}',
        Return(:final exps) => 'return ${exps.s(', ')}',
        Break() => 'break',
        Assign(:final vars, :final exps) => '${vars.s(', ')} = ${exps.s(', ')}',
        Or(:final left, :final right) => '${left.s} or ${right.s}',
        And(:final left, :final right) => '${left.s} and ${right.s}',
        Lt(:final left, :final right) => '${left.s} < ${right.s}',
        Gt(:final left, :final right) => '${left.s} > ${right.s}',
        Le(:final left, :final right) => '${left.s} <= ${right.s}',
        Ge(:final left, :final right) => '${left.s} >= ${right.s}',
        Ne(:final left, :final right) => '${left.s} ~= ${right.s}',
        Eq(:final left, :final right) => '${left.s} == ${right.s}',
        Concat(:final left, :final right) => '${left.s} .. ${right.s}',
        Add(:final left, :final right) => '${left.s} + ${right.s}',
        Sub(:final left, :final right) => '${left.s} - ${right.s}',
        Mul(:final left, :final right) => '${left.s} * ${right.s}',
        Div(:final left, :final right) => '${left.s} / ${right.s}',
        Mod(:final left, :final right) => '${left.s} % ${right.s}',
        Pow(:final left, :final right) => '${left.s} ^ ${right.s}',
        Not(:final exp) => 'not ${exp.s}',
        Neg(:final exp) => '-${exp.s}',
        Len(:final exp) => '#${exp.s}',
        Lit(:final value) => value == nil ? 'nil' : '"$value"',
        Var(:final name) => name,
        Index(:final table, :final key) => '${table.s}[${key.s}]',
        MethCall(:final receiver, :final method, :final args) => '${receiver.s}:$method(${args.s(', ')})',
        FuncCall(:final func, :final args) => '${func.s}(${args.s(', ')})',
        Func(:final params, :final block) => 'function(${params.join(', ')}) ${block.s} end',
        TableConst(:final fields) => '{${fields.map((f) => '${f.key}: ${f.value.s}').join('; ')})}',
        Exp() => throw UnimplementedError(),
      };
}

extension on List<Exp> {
  String s(String sep) => map((e) => e.s).join(sep);
}
