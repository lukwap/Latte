module Compiler where

import Control.Monad.State

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


type Code = String

data ClassDeff = ClassDeff
              { className ::  Ident
              , parent :: Maybe (Ident)
              , attrs :: M.Map Ident Type
              , methods :: M.Map Ident Type
              }

type EnvMap = M.Map Ident (Int, Type) -- int position in stock, type you know

data AsData = AsData
           {
             label :: Int
           , stackSize :: Int
           }

-- klasy $
-- metody _
data  CEnv = CEnv
           { env :: EnvMap
           , strings :: M.Map String String
           , fEnv :: M.Map Ident Type
           , clsEnv :: M.Map Ident ClassDeff
           , utils :: AsData
           }

type Compile = State CEnv

initStore :: CEnv
initStore = CEnv M.empty M.empty M.empty M.empty initAsData

initAsData :: AsData
initAsData = AsData 0 0

prolog :: Code
prolog = unlines [
               ".globl _main"
               ]

compilationProcess :: Program -> String
compilationProcess prog =
    prolog ++ (evalState (compileProg prog) (initStore))

compileProg :: Program -> Compile Code
compileProg prog = do
    strings <- compileStringLabels prog
    prepareFunctions prog
    prepareClasses prog
    insides <- compileProgram prog
    return $ strings ++ insides ++ endOfLine

compileProgram :: Program -> Compile Code
compileProgram (Prog topDefs) = compileTopDefs topDefs

prepareFunctions :: Program -> Compile ()
prepareFunctions (Prog topDefs) = do
    prepareProgFunctions topDefs
    addBuiltInFunctions
    return ()

--TODO not in basic mode
prepareClasses :: Program -> Compile ()
prepareClasses prog = return ()


addBuiltInFunctions :: Compile ()
addBuiltInFunctions = do
    cEnv <- get
    let funcs = fEnv cEnv
    let funcsMod = M.insert (Ident "concat") Void funcs
    let funcsMod1 = M.insert (Ident "new_str") Str funcsMod
    let funcsMod2 = M.insert (Ident "error") Void funcsMod1
    let funcsMod3 = M.insert (Ident "printInt") Void funcsMod2
    let funcsMod4 = M.insert (Ident "printString") Void funcsMod3
    let funcsMod5 = M.insert (Ident "readInt") Int funcsMod4
    let funcsMod6 = M.insert (Ident "readString") Str funcsMod5
    put (CEnv (env cEnv) (strings cEnv) (funcsMod6) (clsEnv cEnv) (utils cEnv))


prepareProgFunctions :: [TopDef] -> Compile ()
prepareProgFunctions [] = return ()
prepareProgFunctions ((FnDef (FunDef t ident _ _)):rest) = do
    cEnv <- get
    let funcEnv = fEnv cEnv
    put (CEnv (env cEnv) (strings cEnv) (M.insert ident t funcEnv) (clsEnv cEnv) (utils cEnv))
    prepareProgFunctions rest
prepareProgFunctions ((ClassDef _ _ ):rest) = prepareProgFunctions rest
prepareProgFunctions ((ClassDefExt _ _ _):rest) = prepareProgFunctions rest


-- strings extraction part --
compileStringLabels :: Program -> Compile Code
compileStringLabels prog = do
--    traceShowM ("Jestem w compileStringLabels")
    let strings = getStrings prog
--    traceShowM ("Strings" ++ show strings)
    stringsToLabels <- mapStrings strings 0
    if (length(stringsToLabels) /= 0) then
        return $ ".data\n"  ++ stringsToLabels
    else
        return $ ""

mapStrings :: [String] -> Int -> Compile String
mapStrings [] _ = return ""
mapStrings (string:rest) lab = do
    cEnv <- get
    let stringMap = strings cEnv
    case M.lookup string stringMap of
        Just label -> mapStrings rest lab
        Nothing -> do
           let stringLine = ".STR" ++ show lab ++ ":\n\t.string \"" ++ string ++ "\"" ++ endOfLine
           put (CEnv (env cEnv) (M.insert string (".STR" ++ show lab) stringMap) (fEnv cEnv) (clsEnv cEnv) (utils cEnv))
           restStrings <- mapStrings rest (lab + 1)
           return $ stringLine ++ restStrings




--helper function for removing duplicates
removeDuplicates :: [String] -> [String]
removeDuplicates = rdHelper []
    where rdHelper seen [] = seen
          rdHelper seen (x:xs)
              | x `elem` seen = rdHelper seen xs
              | otherwise = rdHelper (seen ++ [x]) xs


getStrings :: Program -> [String]
getStrings (Prog topDefs) = removeDuplicates (getStringsTopDefs topDefs)

getStringsTopDefs :: [TopDef] -> [String]
getStringsTopDefs [] = []
getStringsTopDefs (topDef:rest) = (getStringsTopDef topDef) ++ (getStringsTopDefs rest)

getStringsTopDef :: TopDef -> [String]
getStringsTopDef (FnDef (FunDef t ident args (Block stmts))) = getStringsStmts stmts
getStringTopDef (ClassDef id cdef) = getStringsCDef cdef
getStringTopDef (ClassDefExt ident parent cdef) = getStringsCDef cdef

getStringsCDef :: CDef -> [String]
getStringsCDef (ClassBlock classElems) = concat $ map (getStringsClassElems) classElems

getStringsClassElems :: ClassElem -> [String]
getStringsClassElems (ClassMeth (FunDef t ident args (Block stmts))) = getStringsStmts stmts
getStringsClassElems (ClassAtr t ident) = return []

getStringsStmts :: [Stmt] -> [String]
getStringsStmts [] = []
getStringsStmts (stmt:rest) = (getStringsStmt stmt) ++ (getStringsStmts rest)

getStringsStmt :: Stmt -> [String]
getStringsStmt (Empty) = []
getStringsStmt (BStmt (Block stmts)) = getStringsStmts stmts
getStringsStmt (Decl Str []) = []
getStringsStmt (Decl Str items) = concat $ map (getStringsItem) items
getStringsStmt (Ass lval exp) = (getStringsLValue lval) ++ (getStringsExp exp)
getStringsStmt (Ret exp) = getStringsExp exp
getStringsStmt (Cond exp stmt) = (getStringsExp exp) ++ (getStringsStmt stmt)
getStringsStmt (CondElse exp lhsStmt rhsStmt) = (getStringsExp exp) ++
            (getStringsStmt lhsStmt) ++ (getStringsStmt rhsStmt)
getStringsStmt (While exp stmt) = (getStringsExp exp) ++ (getStringsStmt stmt)
getStringsStmt (For typ ident arrayIdent stmt) = getStringsStmt stmt
getStringsStmt (SExp exp) = getStringsExp exp
getStringsStmt _ = []

getStringsItem :: Item -> [String]
getStringsItem (Init ident exp) = getStringsExp exp
getStringsItem (NoInit ident) = [""]

getStringsExp :: Expr -> [String]
getStringsExp (EApp (FunctionCall ident exps)) = concat (map (getStringsExp) exps)
getStringsExp (EString string) = [string]
getStringsExp (EAdd lhsExp addOp rhsExp) = (getStringsExp lhsExp) ++ (getStringsExp rhsExp)
getStringsExp (ERel lhsExp relOp rhsExp) = (getStringsExp lhsExp) ++ (getStringsExp rhsExp)
getStringsExp (EAnd lhsExp rhsExp) = (getStringsExp lhsExp) ++ (getStringsExp rhsExp)
getStringsExp (EOr lhsExp rhsExp) = (getStringsExp lhsExp) ++ (getStringsExp rhsExp)
getStringsExp _ = []

--TODO ??
getStringsLValue _ = []

compileTopDefs :: [TopDef] -> Compile Code
compileTopDefs [] = return ""
compileTopDefs ((FnDef funDef):rest) = do
--    traceShowM ("Parsing function " ++ show funDef)
    funDef <- compileFunDef funDef
--    traceShowM ("Parsed function moving to rest")
    rest <- compileTopDefs rest
    return $ funDef ++ rest
--TODO classes not done
compileTopDefs ((ClassDef id cdef):rest) = compileTopDefs rest
compileTopDefs ((ClassDefExt ident parent cdef):rest) = compileTopDefs rest


compileFunDef :: FuncDef -> Compile Code
compileFunDef (FunDef _ ident args block) = do
    let functionStart = printGlobalFunLabel ident
    cEnv <- get
    prepareFunArgs args 4 -- first 4 is occupied by return address
--    traceShowM ("Parsed function args")
    blockCode <- compileBlock block
--    traceShowM ("After block")
    cEnv' <- get
    let lab = label $ utils $ cEnv'
    let modUtils = AsData lab (stackSize $ utils $ cEnv)
    put (CEnv (env cEnv) (strings cEnv) (fEnv cEnv) (clsEnv cEnv) (modUtils))
    let functionCode = functionStart ++ functionEntry ++ blockCode
    lastStmtRet <- functionEndsWithRet block
    if (lastStmtRet) then
        return functionCode
    else
        return $ functionCode ++ functionLeave

functionEndsWithRet :: Block -> Compile Bool
functionEndsWithRet (Block stmts) =
    if (length(stmts) == 0) then
        return False
    else do
        let lastStmt = last stmts
        case lastStmt of
            VRet -> return True
            Ret exp -> return True
            _ -> return False

--args are already reversed
prepareFunArgs :: [Arg] -> Int -> Compile ()
prepareFunArgs [] size = return ()
prepareFunArgs ((Arg typ ident):args) lastPos = do
    cEnv <- get
    let argSize = getSize typ
    let env_ = env cEnv
    let argPos = lastPos + argSize
    put (CEnv (M.insert ident (argPos,typ) env_) (strings cEnv) (fEnv cEnv) (clsEnv cEnv) (utils cEnv))
    prepareFunArgs args argPos


-- ifdef BLOCK utils

compileBlock :: Block -> Compile Code
compileBlock (Block stmts) = do
    stackSizeForVars <- countVars stmts
--    traceShowM ("Counting vars")
    let subEsp = sub ("$" ++ show stackSizeForVars) esp
    stmtsCodeArr <- mapM (compileStmt) stmts
--    traceShowM ("compiling stmts")
    return $ subEsp ++ (concat stmtsCodeArr)

countVars :: [Stmt] -> Compile Int
countVars [] = return 0
countVars (stmt:rest) = do
    stmtSize <- countVarsStmt stmt
    restSize <- countVars rest
    let wholeSize = stmtSize + restSize
    return wholeSize

countVarsStmt :: Stmt -> Compile Int
countVarsStmt (Decl typ items) = return $  (*) (getSize typ) (length items)
countVarsStmt (Cond exp stmt) = countVarsStmt stmt
countVarsStmt (CondElse exp lhsStmt rhsStmt) = do
    lhsSize <- countVarsStmt lhsStmt
    rhsSize <- countVarsStmt rhsStmt
    return $ lhsSize + rhsSize
countVarsStmt (While exp stmt) = countVarsStmt stmt
countVarsStmt (BStmt (Block stmts)) = countVars stmts
countVarsStmt (For _ _ _ _) = return 4
countVarsStmt _ = return 0
--TODO for FOR STMT add one variable possibly


-- endblock BLOCK utils

-- ifdef STMT
compileStmt :: Stmt -> Compile Code
compileStmt (Empty) = return "" --consider nop operation
compileStmt (BStmt (Block stmts)) = do
    cEnv <- get
    stmtsCodeArr <- mapM (compileStmt) stmts
    cEnv' <- get
    let labelAfter = label $ utils $ cEnv'
    let modUtils = AsData (labelAfter) (stackSize $ utils $ cEnv)
    put (CEnv (env cEnv) (strings cEnv) (fEnv cEnv) (clsEnv cEnv) (modUtils))
    return $ concat $ stmtsCodeArr
compileStmt (Decl typ items) = do
    declCode <- compileDecl typ items
    return $ declCode
compileStmt (Ass lValue exp) = do
    variablePos <- getLValue lValue
    expCode <- compileExp exp
    let expValtoEax = pop eax
    let varPosToEcx = pop ecx
    let movValue = "\tmov %eax, (%ecx)\n"
    return $ concat [variablePos, expCode , expValtoEax, varPosToEcx, movValue]
compileStmt (Incr lValue) = do
    variablePos <- getLValue lValue
    return $ variablePos ++ (pop eax) ++ "\tadd $1 ,(%eax)\n"
compileStmt (Decr lValue) = do
    variablePos <- getLValue lValue
    return $ variablePos ++ (pop eax) ++ "\tsub $1 ,(%eax)\n"
compileStmt (Ret exp) = do --when returning the result is in eax
    expCode <- compileExp exp
    return $ expCode ++ (pop eax) ++ functionLeave
compileStmt (VRet) = return $ functionLeave
compileStmt (Cond exp stmt) = do
    labelInside <- getNewLabel
    labelAfter <- getNewLabel
    condExpCode <- compileBoolExp exp labelInside labelAfter
    stmtCode <- compileStmt stmt
    return $ condExpCode ++ (printLabel labelInside)
        ++ stmtCode ++ (printLabel labelAfter)
compileStmt (CondElse exp lhsStmt rhsStmt) = do
    labelLhsStmt <- getNewLabel
    labelRhsStmt <- getNewLabel
    labelAfter <- getNewLabel
    condExpCode <- compileBoolExp exp labelLhsStmt labelRhsStmt
    lhsStmtCode <- compileStmt (BStmt (Block [lhsStmt]))
    rhsStmtCode <- compileStmt (BStmt (Block [rhsStmt]))
    return $ concat [condExpCode, (printLabel labelLhsStmt), lhsStmtCode,
         jmp labelAfter,(printLabel labelRhsStmt), rhsStmtCode, (printLabel labelAfter)]
compileStmt (While exp stmt) = do
    labelCond <- getNewLabel
    labelStmt <- getNewLabel
    labelAfter <- getNewLabel
    condCode <- compileBoolExp exp labelStmt labelAfter
    whileStmtCode <- compileStmt (BStmt (Block [stmt]))
    return $ concat [(printLabel labelCond), condCode, (printLabel labelStmt)
        , whileStmtCode, (jmp labelCond), (printLabel labelAfter)]
compileStmt (For typ identElem identArr stmt) = error ("Not defined in basic version")
compileStmt (SExp exp) = do
    expCode <- compileExp exp
    return $ expCode




--enddef STMT

---ifndef declaration block
-- przypisz na wolne miejsca
-- zmodyfikuj env
-- zainicjuj
--TDO po funckji wyzeruj stackSize

compileDecl :: Type -> [Item] -> Compile Code
compileDecl typ [] = return $ ""
compileDecl typ ((NoInit ident):rest) = do
    cEnv <- get
    let lastTakenSize = stackSize $ utils $ cEnv
    let typSize = getSize typ
    let env_ = env cEnv
    let popEax = pop eax
    let popPos = pop ecx
    case typ of
        Int -> do
            expCode <- compileExp (ELitInt 0) -- mov 0 pod ten adres i tyle
            let posTaken = lastTakenSize - typSize
            let modUtils = AsData (label $ utils $ cEnv) (posTaken)
            let movValue = "\tmov %eax, " ++ show posTaken ++ "(%ebp)\n"
            put (CEnv (M.insert ident (posTaken, typ) env_) (strings cEnv) (fEnv cEnv) (clsEnv cEnv) (modUtils))
            restCode <- compileDecl typ rest
            return $ concat [expCode, popEax, movValue, restCode]

        Str -> do
            expCode <- compileExp (EString "")
            let posTaken = lastTakenSize - typSize
            let modUtils = AsData (label $ utils $ cEnv) (posTaken)
            let movValue = "\tmov %eax, " ++ show posTaken ++ "(%ebp)\n"
            put (CEnv (M.insert ident (posTaken, typ) env_) (strings cEnv) (fEnv cEnv) (clsEnv cEnv) (modUtils))
            restCode <- compileDecl typ rest
            return $ concat [expCode, popEax, movValue, restCode]
        Bool -> do
            expCode <- compileExp (ELitTrue)
            let posTaken = lastTakenSize - typSize
            let modUtils = AsData (label $ utils $ cEnv) (posTaken)
            let movValue = "\tmov %eax, " ++ show posTaken ++ "(%ebp)\n"
            put (CEnv (M.insert ident (posTaken, typ) env_) (strings cEnv) (fEnv cEnv) (clsEnv cEnv) (modUtils))
            restCode <- compileDecl typ rest
            return $ concat [expCode, popEax, movValue, restCode]

        _ -> error ("fatal initiation of not basic type shouldnt happen right now" ++ show ident)
compileDecl typ ((Init ident exp):rest) = do
    cEnv <- get
    let lastTakenSize = stackSize $ utils $ cEnv
    let typSize = getSize typ
    let env_ = env cEnv
    let popEax = pop eax
    let popPos = pop ecx
    expCode <- compileExp exp
    let posTaken = lastTakenSize - typSize
    let modUtils = AsData (label $ utils $ cEnv) (posTaken)
    let movValue = "\tmov %eax, " ++ show posTaken ++ "(%ebp)\n"
    put (CEnv (M.insert ident (posTaken,typ ) env_) (strings cEnv) (fEnv cEnv) (clsEnv cEnv) (modUtils))
    restCode <- compileDecl typ rest
    return $ concat [expCode, popEax, movValue, restCode]


--enddef declaration block


--TODO DO OLANIA
compileExp :: Expr -> Compile Code
compileExp (ECastNull typ) = undefined
compileExp (EAttrAccess attrAccess) = undefined
compileExp (EMthCall methodCall) = undefined
compileExp (EArrAccess arrElemAccess) = undefined
compileExp (ENew ident) = undefined
compileExp (ENewArr typ exp) =undefined

--TODO
compileExp (EVar ident) = do
    cEnv <- get
    typeIdent <- getExpType (EVar ident)
    let env_ = env cEnv
    case M.lookup ident env_ of
        Just (place, typ) -> return $ push (getVariablePos place)
        Nothing -> error "Shouldnt happen, lookup of variable identificator"


compileExp (ELitInt int) = return $ push ("$" ++ show int)
compileExp (ELitTrue) = return $ push "$1"
compileExp (ELitFalse) = return $ push "$0"
compileExp (EApp (FunctionCall ident exprs)) = do
    cEnv <- get
    let funcs = fEnv cEnv
    case M.lookup ident funcs of
        Just typ -> do
            expsCodeArr <- mapM (compileExp) (reverse exprs)
            let expsCode = concat expsCodeArr
            let fnName = getFuncName ident
            let fnCode = concat [
                                 expsCode,
                                 "\tcall __" ++  fnName ++ endOfLine,
                                 "\tadd $" ++ show (4 * (length exprs)) ++ ", %esp\n"
                                 ]
            case typ of
                Void -> return $ fnCode
                _ -> return $ fnCode ++ (push eax)

        Nothing -> do
            traceShowM ("Functions env" ++ show funcs)
            error ("Shouldnt happen, searching for function ident" ++ show ident ++ show funcs)

compileExp (EString str) = do
    cEnv <- get
    let stringLabels = strings cEnv
    case M.lookup str stringLabels of
        Just label -> do
            return $ concat [ push  ("$" ++ label), call (Ident "__new_str"), add "$4" esp, push eax]
        Nothing -> error ("Shouldnt happen, searching for string label:" ++ str)
compileExp (Neg exp) = do
    expCode <- compileExp exp
    let popEax = pop eax
    let negate = instrL "neg %eax"
    return $ expCode ++ popEax ++ negate ++ (push eax)
compileExp (Not exp) = do
    labelNext <- getNewLabel
    boolCode <- (compileBoolExp (Not exp) labelNext labelNext)
    return $ boolCode ++ (printLabel labelNext)
compileExp (EMul lhsExp mulOp rhsExp) = do
    lhsCode <- compileExp lhsExp
    rhsCode <- compileExp rhsExp
    let expCode = lhsCode ++ rhsCode
    case mulOp of
        Times -> return $ expCode ++ (pop eax) ++ instrL("imul 0(%esp), %eax") ++ mov eax "0(%esp)"
        Div -> return $ expCode ++ divideOp ++ push eax
        Mod -> return $ expCode ++ divideOp ++ push edx

compileExp (EAdd lhsExp Plus rhsExp) = do
    lhsCode <- compileExp lhsExp
    rhsCode <- compileExp rhsExp
    expType <- getExpType lhsExp
    let expCode = lhsCode ++ rhsCode
    case expType of
        Int ->
            return $ expCode ++ pop eax ++ (instrL  ("add 0(%esp), " ++ eax)) ++ mov eax "0(%esp)"
        Str ->
            return $ rhsCode ++ lhsCode ++ concatStrings
        _ -> error "Shouldnt happen, shitty type when adding two exps"

compileExp (EAdd lhsExp Minus rhsExp) = do
    lhsCode <- compileExp lhsExp
    rhsCode <- compileExp rhsExp
    return $ concat [lhsCode, rhsCode, pop eax, pop ecx, sub eax ecx, push ecx]

--only logic expressions hit here
compileExp exp = do
    lTrue <- getNewLabel
    lFalse <- getNewLabel
    lAfter <- getNewLabel
    expCode <- compileBoolExp exp lTrue lFalse
    let pushTT = printLabel lTrue ++ push "$1" ++ jmp lAfter
    let pushFalse = printLabel lFalse ++ push "$0"
    return $ concat [expCode, pushTT, pushFalse, printLabel lAfter]
    

--previous  version - pain in the ass
--    lhsCode <- compileExp lhsExp
--    rhsCode <- compileExp rhsExp
--    let cmp = "pop ebx\npop eax\ncmp eax, ebx\n"
--    let expCode = lhsCode ++ rhsCode
--    labTrue <- getNewLabel
--    labEnd <- getNewLabel
--    let relOpCode = getRelOpCode relOp
--    let pushTrue = "push $1\n"
--    let pushFalse = "push $0\n\tjmp"
--    return $ expCode ++ cmp ++ relOpCode ++ labTrue ++ pushFalse ++ labEnd ++ endOfLine
--            ++ (printLabel labTrue) ++ pushTrue ++ (printLabel labEnd)


-- compileExp e = do
--     traceShowM ("LOL wtf" ++ show e)
--     error ("wtf" ++ show e)
--TODO different procedure for comparing strings - nope we treat string like in java
compileBoolExp :: Expr -> Code -> Code -> Compile Code
compileBoolExp e lTrue lFalse = do
    case e of
        Not exp -> compileBoolExp exp lFalse lTrue
        EAnd lhsExp rhsExp -> do
            lMid <- getNewLabel
            lhsCode <- compileBoolExp lhsExp lMid lFalse
            let lMidCode = printLabel lMid
            rhsCode <- compileBoolExp rhsExp lTrue lFalse
            return $ lhsCode ++ lMidCode ++ rhsCode
        EOr lhsExp rhsExp -> do
            lMid <- getNewLabel
            lhsCode <- compileBoolExp lhsExp lTrue lMid
            let lMidCode = printLabel lMid
            rhsCode <- compileBoolExp rhsExp lTrue lFalse
            return $ lhsCode ++ lMidCode ++ rhsCode
        ERel lhsExp relOp rhsExp -> do
            lPushFalse <- getNewLabel
            lhsCode <- compileExp lhsExp
            rhsCode <- compileExp rhsExp
            let expCode = lhsCode ++ rhsCode
            let popLhsVar = pop eax
            let popRhsVar = pop ecx
            let cmpCode = cmp eax ecx
            let cmpJump = instrL ((getRelOpCode relOp) ++ lPushFalse)
            let pushTrue = push "$1"
            let gotoEnd = jmp lTrue
            let lFalseLabel = printLabel lPushFalse
            let pushFalse = push "$0"
            let jmpFalse = jmp lFalse
            return $ concat [expCode, popLhsVar, popRhsVar, cmpCode, cmpJump, pushTrue, gotoEnd, lFalseLabel
                ,pushFalse, jmpFalse]
        _ -> do
            expCode <- compileExp e
            return $ concat [expCode, pop eax, cmp "$0" eax , jnz lTrue, jmp lFalse]


getVariableStackPos :: Ident -> Compile Code
getVariableStackPos ident = do
    cEnv <- get
    let env_ = env cEnv
    case M.lookup ident env_ of
        Just (place, typ) -> return $ show place
        Nothing -> error ("Fatal error when retrieving ident position on stack" ++ show ident)

getLValue :: LValue -> Compile Code
getLValue (LVFunCall funcCall) = compileExp (EApp funcCall)
getLValue (LVMethodCall (MCall lval funcCall)) = error "Shouldnt happen right now"
getLValue (LVJustIdent ident) = do
    stackPos <- getVariableStackPos ident
    return $ "\tlea " ++ stackPos ++ "(%ebp), " ++ eax ++ "\n" ++ (push eax)
getLValue (LVArrayAcc arrElemAccess) = error "Array access inaccessible in basic mode"
getLValue (LVAttrAcc attrAccess) = error "Attribute acces inaccessible in basic mode"



clearBoolExpFromStack = "add $4, %esp"
concatStrings = unlines [
  "\tcall __concat",
  "\tadd $8, %esp",
  "\tpush %eax"
  ]

divideOp = pop ebx ++ pop eax ++ mov eax edx ++ instrL "sar $31, %edx"
    ++ instrL "idiv %ebx"

getVariablePos :: Int -> Code
getVariablePos pos = show pos ++ "(%ebp)"

--def block expType
getExpType :: Expr -> Compile Type
getExpType ( ECastNull typ) =  return typ
getExpType ( EAttrAccess attrAccess) = undefined
getExpType ( EMthCall mthCall) = undefined
getExpType ( EArrAccess arrElemAccess) = undefined
getExpType ( EVar ident) = do
    cEnv <- get
    let env_ = env cEnv
    case M.lookup ident env_ of
        Just (size, typ) -> return typ
        Nothing -> error ("Shouldnt happen, lookup of Variable" ++ show ident)
getExpType ( ENewArr typ exp) = undefined
getExpType ( ENew ident) = undefined
getExpType ( ELitInt int) = return Int
getExpType ( ELitTrue) = return Bool
getExpType ( ELitFalse) = return Bool
getExpType ( EApp (FunctionCall ident exp)) = do
    cEnv <- get
    let funcs = fEnv cEnv
    case M.lookup ident funcs of
        Just typ -> return typ
        Nothing -> do
            traceShowM ("Funcs env EApp" ++ show funcs)
            error ("Fatal, shouldnt happen lookup of function ident" ++ show ident)
getExpType ( EString str) = return Str
getExpType ( Neg exp) = return Bool
getExpType ( Not exp) = return Bool
getExpType ( EMul lhsExp _ rhsExp) = return Int
getExpType ( EAdd lhsExp Plus rhsExp) = getExpType lhsExp
getExpType ( EAdd lhsExp Minus rhsExp) = return Int
getExpType ( ERel lhsExp _ rhsExp) = return Bool
getExpType ( EAnd lhsExp rhsExp) = return Bool
getExpType ( EOr lhsExp rhsExp) = return Bool


getLValueType :: LValue -> Compile Type
getLValueType (LVJustIdent ident) = do
    cEnv <- get
    let env_ = env cEnv
    case M.lookup ident env_ of
        Just (size, typ) -> return typ
        Nothing -> error ("Shouldn't happen, searching for Lvalue Type" ++  show ident)
getLValueType (LVFunCall funcCall) = getExpType (EApp funcCall)
getLValueType (LVMethodCall (MCall lval funcCall)) = undefined
getLValueType (LVArrayAcc (ArrayElem lval exp)) = undefined
getLValueType (LVAttrAcc (AttrAcc lval ident)) = undefined



-- endblock expType


-- def block utils


getFuncName :: Ident -> Code
getFuncName (Ident fnName) = fnName

functionEntry :: Code
functionEntry = "\tpush %ebp\n\tmov %esp, %ebp\n"

functionLeave::Code
functionLeave = "\tleave\n\tret\n"

getNewLabel :: Compile Code
getNewLabel = do
    cEnv <- get
    let util = utils cEnv
    let lab = label util
    let labinc = lab + 1
    put (CEnv (env cEnv) (strings cEnv) (fEnv cEnv) (clsEnv cEnv) (AsData (labinc) (stackSize util)))
    return $  "Label" ++  show lab

printLabel :: Code -> Code
printLabel label = "." ++ label ++ ":" ++ endOfLine

printGlobalFunLabel :: Ident -> Code
printGlobalFunLabel (Ident ident) =
    if (ident == "main") then
       ("_" ++ ident ++ ":" ++ endOfLine)
    else
       ("__" ++ ident ++ ":" ++ endOfLine)

eax = "%eax"
ebx = "%ebx"
ecx = "%ecx"
edx = "%edx"
ebp = "%ebp"
esp = "%esp"

--reversed shit
getRelOpCode :: RelOp -> Code
getRelOpCode LE = "jg ."
getRelOpCode LTH = "jge ."
getRelOpCode GTH = "jle ."
getRelOpCode GE = "jl ."
getRelOpCode EQU = "jne ."
getRelOpCode NE = "je ."


instrGlobal :: Code -> Code
instrGlobal inside = inside ++ endOfLine
instrL :: Code -> Code
instrL inside = tabbed ++ inside ++ endOfLine
tabbed = "\t"
endOfLine = "\n"
call (Ident str) = instrL $ ("call " ++ str)
push src = instrL ("push " ++ src)
pop src = instrL $ ("pop " ++ src)
mov src dst = instrL $ ("mov " ++ src ++ ", " ++ dst)
add lhs rhs = instrL $ ("add " ++ lhs ++ ", " ++ rhs)
sub lhs rhs = instrL $ ("sub " ++ lhs ++ ", " ++ rhs)
test src dst = instrL $ ("test " ++ src ++ ", " ++ dst)
cmp src dst = instrL $ ("cmp " ++ src ++ ", " ++ dst)
jmp label = instrL $ ("jmp ." ++ label)
jnz label = instrL $ ("jnz ." ++ label)

getSize :: Type -> Int
getSize (Arr _) = 8
getSize Int = 4
getSize Str = 4
getSize Bool = 4
getSize (Obj _) = 4
getSize _ = 0

-- end block utils
