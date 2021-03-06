module TypeChecker where

import Control.Monad.State
import Control.Monad.Except
--import Control.Monad.Trans.Except

import System.IO ( stdin, hGetContents, hPutStrLn, stderr )
import System.Environment ( getArgs, getProgName )
import System.Exit
import LexLatte
import ParLatte
import SkelLatte
import PrintLatte
import AbsLatte
import Data.Int
import Data.Bool
import Data.Graph
import Control.Monad
import Debug.Trace

import qualified Data.Map as M

type TypeError = String

data ClassDeff = ClassDeff
              { className ::  Ident
              , parent :: Maybe (Ident)
              , attrs :: M.Map Ident Type
              , methods :: M.Map Ident Type
              }
instance Show ClassDeff where
    show classDeff = "className " ++ show (className classDeff) ++
            "\n parent" ++ show (parent classDeff) ++ "\n" ++
             "attrs " ++ show (attrs classDeff) ++ "\n" ++
             "methods" ++ show (methods classDeff) ++ "end classdeff\n"
data Context = Context 
            { functions :: M.Map Ident Type
            , attributes :: M.Map Ident Type
              }
instance Show Context where
    show con = "functions " ++ show (functions con)++ " attrs " ++ show (attributes con)

data Env = Env
           { locals :: Context
           , globals :: Context
           , classes :: M.Map Ident ClassDeff
           }
instance Show Env where
    show env = "Env, locals  : \n" ++ show (locals env) ++
        "\n globals "++ show (globals env) ++
        "\n classDeffs" ++ show (classes env)
type Eval = ExceptT (Error) (State Env)

data Error
  =
    DummyError String
  | IntOutofBounds Integer
  | SubstractionTypeError Expr
  | AdditionTypeError Expr
  | ComparisonTypeError Expr
  | OrAndTypeError Expr Expr
  | TypeMismatch Type Type
  | MainFunctionMissing
  | MainFunctionArgsMismatch
  | MainFunctionRetTypeMismatch
  | FunctionArgumentVoidType String
  | FunctionArgumentNameDuplicated String
  | VariableAlreadyDefined String
  | ClassAlreadyDefined String
  | CyclicClassInheritance
  | VariableNotFoundInContext String
  | ReturnStmtMissing
  | IncDecWrongType LValue
  | WrongRetType Type Type
  | VoidDeclarationType [Item]
  | VoidAttributeDeclaration Ident
  | ClassNotDeclared Ident
  | WrongArrayTypeDecl Type
  | WrongNullCast Type
  | FunctionDeclMissing Ident
  | FunctionCallWrongNumberOfArgs Ident Int Int
  | FunctionArgsTypeMismatch Ident Type Type
  | ExpectedArrayType Type
  | ExpectedObjectType Type
  | ClassAttrNotFound Type Ident
  | ArrayAttrUnsupported Ident
  deriving (Eq, Ord)

instance Show Error where
    show (DummyError str) = "Durny blad" ++ show str
    show (IntOutofBounds integer) = "Integer is out of bounds" ++ show integer
    show (SubstractionTypeError exp) = "Wrong type of substraction, expected int " ++ show exp
    show (AdditionTypeError exp) = "Wrong type of addition, expected Int or String in " ++ show exp
    show (ComparisonTypeError exp) ="Wrong type of Comparison, expected Int " ++ show exp
    show (OrAndTypeError exp1 exp2) = "Wrong type in Or/And expression  between" ++ show exp1 ++ " and " ++ show exp2
    show (TypeMismatch t1 t2) = "Expected type " ++ show t1 ++ "got type "++ show t2
    show (MainFunctionMissing) = "Main function is missing"
    show (MainFunctionArgsMismatch) = "Wrong amount of arguments in main function"
    show (MainFunctionRetTypeMismatch) = "Wrong return type in main function"
    show (FunctionArgumentVoidType str) = "Trying to pass void argument to function" ++ show str
    show (FunctionArgumentNameDuplicated str) = "Duplicated argument names  in function" ++ show str
    show (VariableAlreadyDefined str) = "Variable is already defined" ++ str
    show (ClassAlreadyDefined str) = "Class is already defined" ++ str
    show (CyclicClassInheritance) = "Cyclic class inheritance deteced"
    show (VariableNotFoundInContext str) = " No such variable was found in context" ++ show str
    show (ReturnStmtMissing) = "Return statement is missing"
    show (IncDecWrongType  lvalue) = "Wrong value type is incremented/decremented" ++ show lvalue
    show (WrongRetType t1 t2) = "Wrong return type: expected " ++ show t1 ++ " when actual is " ++ show t2
    show (VoidDeclarationType items) = "One of declarations is void variable" ++ show items
    show (VoidAttributeDeclaration ident) = "Void attribute declaration" ++ show ident
    show (ClassNotDeclared ident) = "Class is not declared" ++ show ident
    show (WrongArrayTypeDecl t) = "Wrong array type declaration" ++ show t
    show (WrongNullCast t) = "Wrong null cast" ++ show t
    show (FunctionDeclMissing ident) = "Function declaration is missing" ++ show ident
    show (FunctionCallWrongNumberOfArgs ident int1 int2) = "Wrong number of arguments passed to function " ++ show ident ++ "expected " ++ show int1 ++ " got " ++ show int2
    show (FunctionArgsTypeMismatch ident t1 t2) = "In function call there is arguments type mismatch, expected" ++ show t1 ++ " got " ++ show t2
    show (ExpectedArrayType t) = "Expected array type, got " ++ show t
    show (ExpectedObjectType t) = "Expected object type, got " ++ show t
    show (ClassAttrNotFound t ident) = "Class Attribute was not found" ++ show t ++ " in class " ++ show ident
    show (ArrayAttrUnsupported ident) = "This array attribute is not supported " ++ show ident

evalTypes :: Program -> Either Error ()
evalTypes prog =
    fmap (const ()) (runEval initStore (evalProg prog))

runEval s e = evalState (runExceptT e) s

initStore :: Env
initStore = Env (Context M.empty M.empty) (Context M.empty M.empty) M.empty


--mapInsertGlobalVar ident (Fun retType types) = do
addPredefinedMethods :: Eval ()
addPredefinedMethods = do
    mapInsertGlobalVar (Ident "printInt") (Fun Void (Int:[]))
    mapInsertGlobalVar (Ident "printString") (Fun Void (Str:[]))
    mapInsertGlobalVar (Ident "error") (Fun Void [])
    mapInsertGlobalVar (Ident "readInt") (Fun Int [])
    mapInsertGlobalVar (Ident "readString") (Fun Str [])

emptyContext = Context M.empty M.empty

getIdent :: Ident -> String
getIdent (Ident ident) = ident



---- Validating functions and classes --
validateFunction :: Type -> Ident -> [Arg] -> Eval (Ident, Type)
validateFunction retType ident args = do
    args <- validateFunArgs args []
    return (ident, Fun retType args)


validateClass :: Ident -> Maybe Ident -> CDef -> Eval (Ident, ClassDeff)
validateClass name parent (ClassBlock classElems) =  do
    env <- get
    let clsDef = ClassDeff name parent M.empty M.empty
    classDeff <- validateClassDef classElems clsDef
    put env
    return (name, classDeff)

validateClassDef :: [ClassElem] -> ClassDeff -> Eval ClassDeff
validateClassDef []  classDef = return classDef

validateClassDef (ClassMeth(FunDef retType ident args block):rest) classDef = do
  (funIdent, types) <- validateFunction retType ident args
  env' <- mapInsertLocalVar funIdent types 
  let methods' = M.insert funIdent types (methods classDef)
  put env'
  validateClassDef rest (ClassDeff (className classDef) (parent classDef) (attrs classDef) methods')

validateClassDef ((ClassAtr t ident):rest) classDef = do
  when (t == Void) (throwError (VoidAttributeDeclaration ident))
  env' <- mapInsertLocalVar ident t
  let attrs' = M.insert ident t (attrs classDef)
  put env'
  validateClassDef rest (ClassDeff (className classDef) (parent classDef) attrs' (methods classDef)) 


--function arguments validation : no voids, no duplicates
validateFunArgs :: [Arg] -> [String]-> Eval [Type]
validateFunArgs [] _ = return []
validateFunArgs ((Arg t (Ident ident)):args) visited =
    if (t == Void) then
        throwError (FunctionArgumentVoidType ident)
    else
        if (alreadyVisited ident visited) then
            throwError (FunctionArgumentNameDuplicated ident)
        else do
            rest <- validateFunArgs args (ident:visited)
            return (t:rest)

--funct to check duplicated in list of arguments
alreadyVisited :: String -> [String] ->  Bool
alreadyVisited argName [] = False
alreadyVisited argName (arg:xs) =
    if (argName == arg) then
        True
    else
        alreadyVisited argName xs
--END BLOCK---


-- BLOCK mapInserts Local global, classes -

--TODO maybe empty unit return type, decide

mapInsertLocalVar :: Ident -> Type -> Eval Env
mapInsertLocalVar ident (Fun retType types) = do
    env <- get
    let loc = locals env
    let locFun = functions loc
    let locAttrs = attributes loc
    case M.lookup ident locFun of
        Just (_) -> throwError (VariableAlreadyDefined (getIdent ident))
        Nothing -> do
            let locFun' = M.insert ident (Fun retType types) locFun
            return (Env (Context locFun' locAttrs) (globals env) (classes env))

mapInsertLocalVar ident t = do
    env <- get
    let loc = locals env
    let locAttrs = attributes loc
    let locFun = functions loc
    case M.lookup ident locAttrs of
      Just (_) -> throwError (VariableAlreadyDefined (getIdent ident))
      Nothing -> do
        let locAttrs' = M.insert ident t locAttrs
        return (Env (Context locFun locAttrs') (globals env) (classes env))


--no need to return env if it is a global variable --
mapInsertGlobalVar :: Ident -> Type -> Eval ()
mapInsertGlobalVar ident (Fun retType types) = do
    env <- get
    let glob = globals env
    let globFun = functions glob
    let globAttrs = attributes glob
    case M.lookup ident globFun of
        Just (_) -> throwError (VariableAlreadyDefined (getIdent ident))
        Nothing -> do
            let globFun' = M.insert ident (Fun retType types) globFun
            put (Env (locals env) (Context globFun' globAttrs) (classes env))
            return ()

mapInsertGlobalVar ident t = do
    env <- get
    let glob = globals env
    let globFun = functions glob
    let globAttrs = attributes glob
    case M.lookup ident globAttrs of
        Just (_) -> throwError (VariableAlreadyDefined (getIdent ident))
        Nothing -> do
            let globAttrs' = M.insert ident t globAttrs
            put (Env (locals env) (Context globFun globAttrs') (classes env))
            return ()

mapInsertClass :: Ident -> ClassDeff -> Eval ()
mapInsertClass ident classDef = do
    env <- get
    let cls = classes env
    case M.lookup ident cls of
        Just (_) -> throwError (ClassAlreadyDefined (getIdent ident))
        Nothing -> do
            put (Env (globals env) (locals env) (M.insert ident classDef cls))

envLookUpClass :: Ident -> Eval ClassDeff
envLookUpClass clsName = do
    env <- get
    let cls = classes env
    case M.lookup clsName cls of
        Just clsDef -> return clsDef
        Nothing -> throwError (ClassNotDeclared clsName)



mapLookUpLocalVar :: Ident -> Eval (Maybe Type)
mapLookUpLocalVar ident = do
    env <- get
    contextLookUpVar (locals env) ident

mapLookUpGlobalVar :: Ident -> Eval (Maybe Type)
mapLookUpGlobalVar ident = do
    env <- get
    contextLookUpVar (globals env) ident

mapLookUpLocalFunc :: Ident -> Eval (Maybe Type)
mapLookUpLocalFunc ident = do
    env <- get
    contextLookUpFunc (locals env) ident

mapLookUpGlobalFunc :: Ident -> Eval (Maybe Type)
mapLookUpGlobalFunc ident = do
    env <- get
    contextLookUpFunc (globals env) ident

contextLookUpFunc :: Context -> Ident -> Eval (Maybe Type)
contextLookUpFunc  context ident = do
    return (M.lookup ident (functions context))

contextLookUpVar :: Context -> Ident -> Eval (Maybe Type)
contextLookUpVar context ident = do
    return (M.lookup ident (attributes context))

envLookUpVar :: Ident -> Eval (Maybe Type)
envLookUpVar ident = do
    localLookup <- mapLookUpLocalVar ident
    case localLookup of
        Just t -> return (Just t)
        Nothing -> do
            globalLookup <- mapLookUpGlobalVar ident
            return globalLookup

envLookUpFunc :: Ident -> Eval (Maybe Type)
envLookUpFunc ident = do
    localLookup <- mapLookUpLocalFunc ident
    case localLookup of
        Just t -> return (Just t)
        Nothing -> do
            globalLookup <- mapLookUpGlobalFunc ident
            return globalLookup



-- END BLOCK INSERTS

--- DEF check classes inheritance

--TODO class method inheritance evalution maybe?
checkClassesInheritance :: Eval ()
checkClassesInheritance = do
  checkClassesAcyclicInheritance


checkClassesAcyclicInheritance :: Eval ()
checkClassesAcyclicInheritance = do
  env <- get
  let classes_ = M.elems (classes env)
  let extractedEdges =  fmap extractClassesEdges classes_
--  traceShowM extractedEdges
  edgesInt <- convertClassesToEdges extractedEdges  M.empty 0 []
  let bounds = (0,  length classes_)
  let graph = buildG bounds edgesInt
--  traceShowM graph
--  traceShowM bounds
--  traceShowM (path graph 0 1)
  if (any (\x -> selfCycle graph x) [0, length classes_] == True) then
      throwError (CyclicClassInheritance)
  else
    return ()

selfCycle :: Graph -> Vertex -> Bool
selfCycle graph x = do
    let dest = reachable graph x
    let reachableWithOutSelf = filter (\elem -> elem /= x) dest
    any (\el -> path graph x el) reachableWithOutSelf

extractClassesEdges :: ClassDeff -> (String, String)
extractClassesEdges classDef = do
  let myName = className classDef
  case parent classDef of 
    Just parentName -> (getIdent myName, getIdent parentName)
    Nothing -> (getIdent myName, "object") 

convertClassesToEdges :: [(String, String)] -> (M.Map String Int) -> Int -> [(Int, Int)] -> Eval [(Int, Int)]
convertClassesToEdges [] edgeHashMap nextInt edgesIntArr = return edgesIntArr 
convertClassesToEdges ((lhs,rhs):rest) edgeHashMap nextInt edgesIntArr = do
  let (nextInt', edgeHashMap') =  insertEdgeIntoHashMap lhs edgeHashMap nextInt
  let (nextInt'', edgeHashMap'') = insertEdgeIntoHashMap rhs edgeHashMap' nextInt'
  case (M.lookup lhs edgeHashMap'') of
    Just lhsInt -> do
      case (M.lookup rhs edgeHashMap'') of
        Just rhsInt -> 
          convertClassesToEdges (rest) (edgeHashMap'') nextInt'' ((lhsInt, rhsInt):edgesIntArr)
        Nothing ->
          throwError (DummyError "not gonna happen")
    Nothing -> 
      throwError (DummyError "not gonna happen2")



checkIfEdgePresent :: String -> (M.Map String Int) -> Bool
checkIfEdgePresent edgeName edgeHashMap = do
  case (M.lookup edgeName edgeHashMap) of
      Just number -> True
--        trace ("True" ++ show (edgeHashMap) ++ " nazwa krawedzi " ++ edgeName)
      Nothing -> False
--        trace ("Falsz" ++ show (edgeHashMap) ++ " nazwa krawedzi " ++ edgeName)

insertEdgeIntoHashMap :: String -> M.Map String Int -> Int -> (Int, M.Map String Int)
insertEdgeIntoHashMap edgeName edgeHashMap nextInt = do
  if ((checkIfEdgePresent edgeName edgeHashMap) == False) then do
    let edgeHashMap' = M.insert edgeName nextInt edgeHashMap
    (nextInt + 1, edgeHashMap')
--    trace ("Po wstawieniu " ++ show edgeHashMap ++ " nastepny int" ++ show nextInt ++ " krawedz wstawiona" ++ edgeName)
  else
    (nextInt, edgeHashMap)

-- END BLOCK CLASS INHERITANCE EVALUTATOR


--- Evaluation of program -----
evalProg :: Program -> Eval ()
evalProg (Prog topdefs) = do
    addPredefinedMethods
    env <- get
    prepareTopDefs topdefs
    checkClassesInheritance
    validateMain topdefs
    checkTopDefs topdefs

--- def block validate main

validateMain :: [TopDef] -> Eval ()
validateMain [] = throwError MainFunctionMissing
validateMain (FnDef(FunDef Int (Ident "main") [] _):_) = return ()
validateMain (FnDef(FunDef _ (Ident "main") [] _):_) = throwError MainFunctionRetTypeMismatch
validateMain (FnDef(FunDef _ (Ident "main") _ _):_) = throwError MainFunctionArgsMismatch
validateMain (_:tl) = validateMain tl

--end block 


prepareTopDefs :: [TopDef] -> Eval ()
prepareTopDefs [] = return () --return enviroment
prepareTopDefs (FnDef(FunDef retType ident args block):topDefs) = do
    (ident, types) <- validateFunction retType ident args
    mapInsertGlobalVar ident types
    prepareTopDefs topDefs

prepareTopDefs ((ClassDef ident classDef):topDefs) = do
    (className, clsDef) <- validateClass ident Nothing classDef
    mapInsertClass className clsDef
    prepareTopDefs topDefs
prepareTopDefs ((ClassDefExt ident parent classDef):topDefs) = do
    (className, clsDef) <- validateClass ident (Just parent) classDef
    mapInsertClass className  clsDef
    prepareTopDefs topDefs



checkTopDefs :: [TopDef] -> Eval ()
checkTopDefs (def:topdefs) = do
    env <- get
--    traceShowM ("sprawdzam topdefa")
    checkTopDef def
--    traceShowM ("po sprawdzeniu")
    put env
    checkTopDefs topdefs
checkTopDefs [] = do
--    traceShowM ("Skonczone topdefy")
    return ()


checkTopDef :: TopDef -> Eval ()
checkTopDef (FnDef func) = do
    checkFuncDef func
checkTopDef (ClassDef name classDef) = do
--    traceShowM ("spradzam klase bez rodzica")
    checkClassDef name Nothing classDef
checkTopDef (ClassDefExt name parent classDef) = do
--    traceShowM ("sprwadzam klase z rodzicem")
    checkClassDef name (Just parent) classDef


checkClassDef :: Ident -> Maybe Ident -> CDef -> Eval ()
checkClassDef ident parentName (ClassBlock classElems) = do
    classCombinedMethods <- combineClassMethods ident M.empty
    classCombinedAttrs <- combineClassAttrs ident M.empty
    env <- get
    let loc = locals env
    let localsMod = Context (M.union classCombinedMethods (functions loc)) (M.union classCombinedAttrs (attributes loc))
    put (Env localsMod (globals env) (classes env))
    checkClassElems classElems
    put env

checkClassElems :: [ClassElem] -> Eval ()
checkClassElems [] = return ()
checkClassElems ((ClassAtr typ ident):xs) = checkClassElems xs
checkClassElems ((ClassMeth funDef):xs) = do
    checkFuncDef funDef
    checkClassElems xs


returnTypeName :: Ident
returnTypeName = (Ident "__ret__")


getReturnType :: Eval Type
getReturnType =  do
    returnType <- envLookUpVar returnTypeName
    case returnType of
        Just t -> return t
        Nothing -> throwError (VariableNotFoundInContext (getIdent returnTypeName))
--throwError (VariableNotFoundInContext (getIdent ident))


checkFuncDef :: FuncDef -> Eval ()
checkFuncDef (FunDef retType ident args (Block stmts)) = do
--  traceShowM ("checkFuncDef blok")
  retEnv <- mapInsertLocalVar returnTypeName retType
--  traceShowM retEnv
  put retEnv
  argsEnv <- checkArgsEnv args
  put argsEnv
  checkRetStmts stmts
  put argsEnv
--  traceShowM ("sprawdzam blok funkcji" ++ show ident)
  checkBlock (Block stmts)
--  traceShowM ("sprawdzilem")
  --now checkstatements, then check return block? of should it be other way
  return ()

checkArgsEnv :: [Arg] -> Eval Env
checkArgsEnv [] = get
checkArgsEnv ((Arg t ident):rest) = do
  env <- mapInsertLocalVar ident t
  put env
  checkArgsEnv rest


checkRetStmts :: [Stmt] -> Eval ()
checkRetStmts [] = do
  retType <- getReturnType
  unless (retType == Void) (throwError ReturnStmtMissing)
checkRetStmts (x:[]) =
    checkRetStmt x
checkRetStmts (x:xs) = do
    env <- (checkStmt x)
    put env
    checkRetStmts xs



checkRetStmt :: Stmt -> Eval ()

checkRetStmt (BStmt (Block stmts)) = do
    env <- get
    checkRetStmts stmts
    put env

checkRetStmt (Ret exp) = do
    env <- get
--    traceShowM ("Env przy ret" ++ show env ++ show exp)
    retType <- getReturnType
    checkType exp retType
    return ()
checkRetStmt (Cond exp stmt) = checkRetStmt (CondElse exp stmt Empty)

checkRetStmt (CondElse ELitTrue lhsStmt _) = checkRetStmt lhsStmt
checkRetStmt (CondElse ELitFalse _ rhsStmt) = checkRetStmt rhsStmt
checkRetStmt (CondElse exp lhsStmt rhsStmt) = do
    checkRetStmt lhsStmt
    checkRetStmt rhsStmt
checkRetStmt (While exp stmt) =
    checkRetStmt stmt
checkRetStmt (For typ ident1 ident2 stmt) =
    checkRetStmt stmt

--inconsequential statements in last block
checkRetStmt _ =  do
    retType <- getReturnType
    unless (retType == Void) (throwError ReturnStmtMissing)
--checkRetStmt (Decl typ [items]) = undefined
--checkRetStmt (Ass lval exp) = undefined
--checkRetStmt (Incr lval) = undefined
--checkRetStmt (Decr lval) = undefined
--checkRetStmt Empty =  do
--    retType <- getReturnType
--    unless (retType == Void) (throwError ReturnStmtMissing)
--checkRetStmt VRet = do
--    retType <- getReturnType
--    unless (retType == Void) (throwError ReturnStmtMissing)
--checkRetStmt (SExp exp) = do
--    retType <- getReturnType
--    unless (retType == Void) (throwError ReturnStmtMissing)


--DEF BLOCK checkStmt

checkBlock :: Block -> Eval ()
checkBlock (Block stmts) = do
  env <- get
  let globalsFuncJoined  = M.union (functions (locals env)) (functions (globals env))
  let globalsAttrJoined = M.union (attributes (locals env)) (attributes (globals env))
  let envModified = (Env (emptyContext) (Context globalsFuncJoined globalsAttrJoined)(classes env))
  put envModified
  checkStmts stmts
  put env

checkStmts :: [Stmt] -> Eval ()
checkStmts [] = return ()
checkStmts (stmt:rest) = do
  env' <- checkStmt stmt
  put env'
  checkStmts rest

checkStmt :: Stmt -> Eval Env
checkStmt Empty = get
checkStmt (BStmt block) = do
    checkBlock block
    get
checkStmt (Decl t items) =
    checkDeclList t items
checkStmt (Ass lvalue exp) = do
    expType <- findType exp
    identType <- findLValueType lvalue
    if (expType == identType) then get
    else do
        checkIfSubClass identType expType
        get
checkStmt (Incr lvalue) = do
    lvalType <- findLValueType lvalue
    unless (lvalType == Int) (throwError (IncDecWrongType lvalue))
    get
checkStmt (Decr lvalue) = do
    lvalType <- findLValueType lvalue
    unless (lvalType == Int) (throwError (IncDecWrongType lvalue))
    get
checkStmt (Ret expr) = do
    expType <- findType expr
    retType <- getReturnType
    if (expType == retType) then get
    else do
        checkIfSubClass retType expType
        get
checkStmt (VRet) = do
    retType <- getReturnType
    unless (retType  == Void) (throwError (WrongRetType (retType) (Void)))
    get
checkStmt (Cond exp stmt) = do
    checkType exp Bool
    checkStmt stmt
checkStmt (CondElse exp stmt1 stmt2) = do
    checkType exp Bool
    checkStmt stmt1
    checkStmt stmt2
checkStmt (While exp stmt) = do
--    traceShowM  ("While exp" ++  show(exp))
    checkType exp Bool
    checkStmt stmt
--TODO implement this sheet
--TODO something fucked up here
checkStmt (For t ident1 ident2 stmt) = do
    arrayExpType <- envLookUpVar ident2
    case arrayExpType of
        (Just typ) ->
            case typ of
                (Arr arrayT)  -> do
                    unless (t == arrayT) (throwError (TypeMismatch t arrayT))
                    env <- get
                    env'<- mapInsertLocalVar ident1 t
                    put env'
                    checkStmt stmt
                    put env
                    return env
                _ -> throwError (ExpectedArrayType typ)
        Nothing -> throwError (VariableNotFoundInContext (getIdent ident2))
checkStmt (SExp exp) = do
    findType exp
    get

checkDeclList :: Type -> [Item] -> Eval Env
checkDeclList _ [] = get
checkDeclList t (item:items) = do
    when (t == Void) (throwError (VoidDeclarationType (item:items)))
    ident <- checkItem item t
    env' <- mapInsertLocalVar ident t
    put env'
    checkDeclList t items

-- end block checkStmt

checkItem :: Item -> Type -> Eval Ident
checkItem (NoInit ident) _ = return ident
checkItem (Init ident exp) t = do
    expType <- findType exp
    if (expType == t) then
        return ident
    else do
        checkIfSubClass t expType
        return ident


--TODO maybe optimize this fucking equal type or subclass

checkIfSubClass :: Type -> Type -> Eval ()
checkIfSubClass (Obj lhs) (Obj rhs) = do
    rhsDef <- envLookUpClass rhs
    case (parent rhsDef)  of
        Nothing -> throwError (TypeMismatch (Obj lhs) (Obj rhs))
        Just parentName -> do
            if lhs == parentName then
                return ()
            else
                checkIfSubClass (Obj lhs) (Obj parentName)
checkIfSubClass x y = throwError (TypeMismatch x y)

combineClassMethods :: Ident -> (M.Map Ident Type) -> Eval (M.Map Ident Type)
combineClassMethods ident map = do
    clsDef <- envLookUpClass ident
    let methodUnion = M.union (methods clsDef) map
    case (parent clsDef) of
        Just parentName -> do
            combineClassMethods parentName methodUnion
        Nothing -> return methodUnion

combineClassAttrs :: Ident -> (M.Map Ident Type) -> Eval (M.Map Ident Type)
combineClassAttrs ident map = do
    clsDef <- envLookUpClass ident
    let attrUnion = M.union (attrs clsDef) map
    case (parent clsDef) of
        Just parentName -> do
            combineClassAttrs parentName attrUnion
        Nothing -> return attrUnion

--DEF BLOCK findTYPE
findLValueType :: LValue -> Eval Type
findLValueType (LVJustIdent ident) = getIdentType ident
findLValueType (LVFunCall funcCall) = findType (EApp funcCall)
findLValueType (LVMethodCall (MCall lval funcCall)) = do
    typ <- findLValueType lval
    case typ of
        (Obj ident) -> do
            clsDef <- envLookUpClass ident
            classMethods <- combineClassMethods ident M.empty
            env <- get
            let loc = locals env
            let localsMod = Context (M.union classMethods (functions loc)) (attributes loc)
            let envMod = Env (localsMod) (globals env) (classes env)
            put envMod
            typ <- findType (EApp funcCall)
            put env
            return typ
        _ -> throwError (DummyError "lel")
findLValueType (LVArrayAcc (ArrayElem lval exp)) = do
    typ <- findLValueType lval
    expType <- findType exp
    unless (expType == Int) (throwError (TypeMismatch expType Int))
    case typ of
        (Arr arrType) -> return arrType
        _ -> throwError (ExpectedArrayType typ)
findLValueType (LVAttrAcc (AttrAcc lval ident)) = do
    typ <- findLValueType lval
    case typ of
        (Obj ident) -> do
            clsDef <- envLookUpClass ident
            classAttrs <- combineClassAttrs ident M.empty
            case M.lookup ident classAttrs of
                Just attrType -> return attrType
                Nothing -> throwError (ClassAttrNotFound (Obj ident) ident)
        _ -> throwError (ExpectedObjectType typ)


--TODO this is fucked up, further consideration needed
getIdentType ident = do
    env <- get
    let classes_ = classes env
    case M.lookup ident classes_ of
        (Just classDef) -> return (Obj ident)
        Nothing -> do
            possibleVar <- envLookUpVar ident
            case possibleVar of
                Just varType -> return varType
                Nothing -> do
                    possibleFun <- envLookUpFunc ident
                    case possibleFun of
                        Just varType -> return varType
                        Nothing -> throwError (VariableNotFoundInContext (getIdent ident))


findType :: Expr -> Eval Type
--TODO sprawdzenie czy taki typ istnieje
findType (ECastNull (Obj ident)) = do
    env <- get
    case (M.lookup ident (classes env)) of
        Just _ -> return (Obj ident)
        Nothing -> throwError (ClassNotDeclared ident)

findType (ECastNull t) =
    throwError (WrongNullCast t)
findType (EAttrAccess (AttrAcc lvalue ident)) = do
    lvalType <- findLValueType lvalue
    case lvalType of
        (Arr t) -> do
            case ident of
                (Ident  "length") -> return Int
                _ -> throwError (ArrayAttrUnsupported ident)
        _ -> findLValueType  (LVAttrAcc (AttrAcc lvalue ident))
findType (EMthCall methCall) = findLValueType (LVMethodCall methCall)
findType (EArrAccess arrElemAcc) = findLValueType (LVArrayAcc arrElemAcc)

findType (EVar ident) = do
    match <- envLookUpVar ident
    case match of
        Just typ -> return typ
        Nothing -> throwError (VariableNotFoundInContext (getIdent ident))
findType (ENewArr (Arr Bool) exp) =
    return (Arr Bool)
findType (ENewArr (Arr Int) exp) =
    return (Arr Int)
findType (ENewArr (Arr Str) exp) = do
    return (Arr Str)
findType (ENewArr (Arr (Obj ident)) exp) = do
    env <- get
    case M.lookup ident (classes env) of
        Just _ -> return (Arr (Obj ident))
        Nothing -> throwError (ClassNotDeclared ident)
findType (ENewArr (Arr t) exp) =
    throwError (WrongArrayTypeDecl t)
findType (ENewArr t exp) =
    throwError (WrongArrayTypeDecl t)

findType (ENew ident) = do
    env <- get
    case M.lookup ident (classes env) of
        Just _ -> return (Obj ident)
        Nothing -> throwError (ClassNotDeclared ident)
findType (ELitInt n) =
    if (((fromIntegral (minBound :: Int32)) < n)
          && ((fromIntegral (maxBound :: Int32)) > n)) then
        return Int
    else do
        throwError (IntOutofBounds n)

findType (ELitTrue) =
    return Bool

findType (ELitFalse) = return Bool


findType (EApp (FunctionCall ident args)) = do
   func <- envLookUpFunc ident
   case func of
    Just (Fun retType argsTypes) -> do
        if (length(args) /= length (argsTypes)) then
            throwError (FunctionCallWrongNumberOfArgs (ident) (length(args)) ((length argsTypes)))
        else do
            argsTypesResolved <- mapM findType args
            let zipped = zip argsTypesResolved argsTypes
            validatePassedArgs ident zipped
            return retType
    Nothing -> throwError (FunctionDeclMissing ident)
-- sprawdz czy funkcja defined
-- sprawdz czy typ zwracany sie zgadza
-- nie dam rady sprawdzic typu
-- sprawdz czy typy argumentow sie zgadzaja
-- walidacja argumentow hmm done


findType (EString _) =
    return Str

findType (Neg expr) =
    checkType expr Int

findType (Not expr) =
    checkType expr Bool

findType (EMul lhs _ rhs) = do
    checkType lhs Int >> checkType rhs Int

findType exp@(EAdd lhs Plus rhs) = do
    joinedType <- checkType rhs =<< (findType lhs)
    let cond = (joinedType `elem` [Int, Str])
    let throwMsg = (AdditionTypeError exp)
    unless cond (throwError throwMsg)
    return joinedType

findType exp@(EAdd lhs Minus rhs) = do
    joinedType <- checkType rhs =<< (findType lhs)
    let cond  = (joinedType == Int)
    let throwMsg = (SubstractionTypeError exp)
    unless cond (throwError throwMsg)
    return joinedType


findType (ERel lhs EQU rhs) = do
    checkType rhs =<< (findType lhs)
    return Bool
findType (ERel lhs NE rhs) = do
    checkType rhs =<< (findType lhs)
    return Bool
findType exp@(ERel lhs op rhs) = do
    joinedType <- checkType rhs =<< (findType lhs)
    unless (joinedType == Int) (throwError (ComparisonTypeError exp))
    return Bool

findType (EAnd lhs rhs) =
    findEAndOr lhs rhs

findType (EOr lhs rhs) =
    findEAndOr lhs rhs

--findType _ = throwError (DummyError "Lel fail")


findEAndOr lhs rhs = do
    joinedType <- checkType rhs =<< (findType lhs)
    let cond = (joinedType == Bool)
    let throwMsg = (OrAndTypeError lhs rhs)
    unless cond  (throwError throwMsg)
    return joinedType


validatePassedArgs :: Ident -> [(Type, Type)] -> Eval ()
validatePassedArgs funIdent [] = return ()
validatePassedArgs funIdent ((actual, expected):xs) =
    if (actual /= expected) then
        throwError (FunctionArgsTypeMismatch (funIdent) (actual) (expected))
    else
        validatePassedArgs funIdent xs


checkType:: Expr -> Type -> Eval Type
checkType exp expectedType = do
    resType <- findType exp
    if (expectedType /= resType) then
--        traceShowM resType
--        traceShowM exp
--        traceShowM expectedType
        throwError (TypeMismatch expectedType resType)
    else
        return resType