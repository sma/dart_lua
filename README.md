# Lua

An untested and incomplete interpreter for Lua 5.1.

I wrote it back in 2013 but it still runs with the most current version of Dart.

The interpreter uses Dart types for the usual Lua values like numbers or strings, as well as `Table` and `UserFunc` instances for, well, Lua tables and functions. Dart functions which conform to the `Fun` Dart type, like `UserFunc` does, can be used to create built-in functions.

Everything is evaluated using `Env`. You need to prepopulate an environment with the usual global Lua functions which aren't given. The `main` function contains an example how to define `print`, but that's it.

The `Parser`, which must be initialized with a `Scanner`, is used to create a hierarchy of `Node`s from source code. They can then be interpreted by calling `eval` and passing an `Env`.

An environment knows its parent and keeps track of variable bindings. You can `bind` new values, `update` existing bindings and `lookup` values. An environment knows which values are _truthy_. There are also utility functions to perform unary and binary operations and do the metatable lookup as required by Lua. It also stores global static metatables for numbers, booleans, strings, and functions. Those should probably be part of a `Lua` system and not static.

To return values from a function call or to break a loop, special `RuntimeExeption` and `BreakException` instances are used which are thrown by the runtime and automatically caught again.

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
