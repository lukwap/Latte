-- automatically generated by BNF Converter
module Main where

import System.IO ( stdin, hGetContents, hPutStrLn, stderr )
import System.Environment ( getArgs, getProgName )
import System.Exit
import Control.Monad (when)
import Control.Monad.State
import Control.Monad.Except
import LexLatte
import ParLatte
import SkelLatte
import PrintLatte
import AbsLatte
import TypeChecker
import Compiler




import ErrM

type ParseFun a = [Token] -> Err a

myLLexer = myLexer

type Verbosity = Int

putStrV :: Verbosity -> String -> IO ()
putStrV v s = when (v > 1) $ putStrLn s

--runFile :: (Print a, Show a) => Verbosity -> ParseFun a -> FilePath -> IO ()
--runFile v p f = putStrLn f >> readFile f >>= run v p

run :: Verbosity -> String -> IO ()
run v s = let ts = myLLexer s in case pProgram ts of
           Bad s    -> do putStrLn "\nParse              Failed...\n"
                          putStrV v "Tokens:"
                          putStrV v $ show ts
                          putStrLn s
                          exitFailure
           Ok  tree -> do putStrLn "\nParse Successful!"
                          showTree v tree
                          case evalTypes tree of
                                    Left error-> do
                                      hPutStrLn stderr $ "ERROR"
                                      putStrLn $ show error
                                      exitFailure
                                    Right _ -> do
                                      hPutStrLn stderr $ "OK"
                                      let compiledCode = compilationProcess tree
                                      putStrLn compiledCode
                                      putStrLn "OK"
--                                      compileProg prog



showTree :: (Show a, Print a) => Int -> a -> IO ()
showTree v tree
 = do
      putStrV v $ "\n[Abstract Syntax]\n\n" ++ show tree
      putStrV v $ "\n[Linearized tree]\n\n" ++ printTree tree

usage :: IO ()
usage = do
  putStrLn $ unlines
    [ "usage: Call with one of the following argument combinations:"
    , "  --help          Display this help message."
    , "  (no arguments)  Parse stdin verbosely."
    , "  (files)         Parse content of files verbosely."
    , "  -s (files)      Silent mode. Parse content of files silently."
    ]
  exitFailure

main :: IO ()
main = do
  args <- getArgs
  case args of
    ["--help"] -> usage
    [] -> getContents >>= run 2
    (path:[]) -> readFile path >>= run 2
    _ -> hPutStrLn stderr $ "Too many arguments"

{-    "-s":fs -> mapM_ (runFile 0 pProgram) fs
    fs -> mapM_ (runFile 2 pProgram) fs-}





