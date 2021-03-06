

module AbsLatte where

-- Haskell module generated by the BNF converter




newtype Ident = Ident String deriving (Eq, Ord, Show, Read)
data Program = Prog [TopDef]
  deriving (Eq, Ord, Show, Read)

data TopDef
    = FnDef FuncDef
    | ClassDef Ident CDef
    | ClassDefExt Ident Ident CDef
  deriving (Eq, Ord, Show, Read)

data Arg = Arg Type Ident
  deriving (Eq, Ord, Show, Read)

data FuncDef = FunDef Type Ident [Arg] Block
  deriving (Eq, Ord, Show, Read)

data CDef = ClassBlock [ClassElem]
  deriving (Eq, Ord, Show, Read)

data ClassElem = ClassMeth FuncDef | ClassAtr Type Ident
  deriving (Eq, Ord, Show, Read)

data Block = Block [Stmt]
  deriving (Eq, Ord, Show, Read)

data Stmt
    = Empty
    | BStmt Block
    | Decl Type [Item]
    | Ass LValue Expr
    | Incr LValue
    | Decr LValue
    | Ret Expr
    | VRet
    | Cond Expr Stmt
    | CondElse Expr Stmt Stmt
    | While Expr Stmt
    | For Type Ident Ident Stmt
    | SExp Expr
  deriving (Eq, Ord, Show, Read)

data Item = NoInit Ident | Init Ident Expr
  deriving (Eq, Ord, Show, Read)

data Type
    = Arr Type | Int | Str | Fun Type [Type] | Bool | Void | Obj Ident
  deriving (Eq, Ord, Show, Read)

data Expr
    = ECastNull Type
    | EAttrAccess AttrAccess
    | EMthCall MethodCall
    | EArrAccess ArrElemAccess
    | EVar Ident
    | ENewArr Type Expr
    | ENew Ident
    | ELitInt Integer
    | ELitTrue
    | ELitFalse
    | EApp FunctionCall
    | EString String
    | Neg Expr
    | Not Expr
    | EMul Expr MulOp Expr
    | EAdd Expr AddOp Expr
    | ERel Expr RelOp Expr
    | EAnd Expr Expr
    | EOr Expr Expr
  deriving (Eq, Ord, Show, Read)

data FunctionCall = FunctionCall Ident [Expr]
  deriving (Eq, Ord, Show, Read)

data ArrElemAccess = ArrayElem LValue Expr
  deriving (Eq, Ord, Show, Read)

data AttrAccess = AttrAcc LValue Ident
  deriving (Eq, Ord, Show, Read)

data MethodCall = MCall LValue FunctionCall
  deriving (Eq, Ord, Show, Read)

data LValue
    = LVFunCall FunctionCall
    | LVMethodCall MethodCall
    | LVJustIdent Ident
    | LVArrayAcc ArrElemAccess
    | LVAttrAcc AttrAccess
  deriving (Eq, Ord, Show, Read)

data AddOp = Plus | Minus
  deriving (Eq, Ord, Show, Read)

data MulOp = Times | Div | Mod
  deriving (Eq, Ord, Show, Read)

data RelOp = LTH | LE | GTH | GE | EQU | NE
  deriving (Eq, Ord, Show, Read)

