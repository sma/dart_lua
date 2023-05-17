# Lua

An untested and incomplete interpreter for Lua 5.1.

The interpreter uses Dart types for the usual Lua values like numbers or strings, as well as `Table` and `UserFunc` instances for, well Lua tables and functions. Dart functions which conform to the `Fun` Dart type like `UserFunc` does, can be used to create built-in functions.

Everything is evaluated using `Env`. You need to repopulate an environment with the usual global Lua functions which aren't really given. The `main` function contains an example how to define `print` but that's all.

The `Parser`, which must be initialized with a `Scanner`, is used to create a hierachy of `Node`s from source code. Can then be interpreted by calling `eval` and passing an `Env`.

An environment knows its parent and keeps track of variable bindings. You can `bind` new values, `update` existing bindings and `lookup` values. An environment knows which values are _truthy_. There are also utility functions to perform unary and binary operations and do the metatable lookup as required by Lua. It also stores global static metatables for numbers, booleans, strings, and functions. Those should probably be part of a `Lua` system and not static.

To return values from a function call or to break a loop, special `RuntimeExeption` and `BreakException` instances are used which are thrown by the runtime and automatically catched again.

Here's the node hierarchy:

    Node
        Stat
            Block
            While
            Repeat
            If
            NumericFor
            GenericFor
            FuncDef
            MethDef
            LocalFuncDef
            Local
            Return
            Break
            Assign
        Exp
            Bin
                Or
                And
                Lt
                Gt
                Le
                Ge
                Ne
                Eq
                Concat
                Add
                Sub
                Mul
                Div
                Mod
                Pow
            Un
                Not
                Neg
                Len
            Lit
            Var
            Index
            Call
                MethCall
                FuncCall
            Func
            TableConst
