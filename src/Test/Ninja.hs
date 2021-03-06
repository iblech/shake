
module Test.Ninja(main) where

import Development.Shake
import qualified Development.Shake.Config as Config
import System.Directory(copyFile, createDirectoryIfMissing, removeFile)
import Control.Applicative
import Control.Monad
import Test.Type
import qualified Data.HashMap.Strict as Map
import Data.List
import Data.Maybe
import System.IO.Extra
import qualified Run
import System.Environment
import Prelude


main = shaken test $ \args obj -> do
    let args2 = ("-C" ++ obj "") : map tail (filter ("@" `isPrefixOf`) args)
    let real = "real" `elem` args
    action $
        if real then cmd "ninja" args2 else liftIO $ withArgs args2 Run.main


test build obj = do
    -- when calling run anything with a leading @ gets given to Shake, anything without gets given to Ninja
    let run xs = build $ "--exception" : map (\x -> fromMaybe ('@':x) $ stripPrefix "@" x) (words xs)
    let runFail xs bad = assertException [bad] $ run $ xs ++ " --quiet"

    build ["clean"]
    run "-f../../src/Test/Ninja/test1.ninja"
    assertExists $ obj "out1.txt"

    run "-f../../src/Test/Ninja/test2.ninja"
    assertExists $ obj "out2.2"
    assertMissing $ obj "out2.1"
    build ["clean"]
    run "-f../../src/Test/Ninja/test2.ninja out2.1"
    assertExists $ obj "out2.1"
    assertMissing $ obj "out2.2"

    copyFile "src/Test/Ninja/test3-sub.ninja" $ obj "test3-sub.ninja"
    copyFile "src/Test/Ninja/test3-inc.ninja" $ obj "test3-inc.ninja"
    createDirectoryIfMissing True $ obj "subdir"
    copyFile "src/Test/Ninja/subdir/1.ninja" $ obj "subdir/1.ninja"
    copyFile "src/Test/Ninja/subdir/2.ninja" $ obj "subdir/2.ninja"
    run "-f../../src/Test/Ninja/test3.ninja"
    assertContentsWords (obj "out3.1") "g4+b1+++i1"
    assertContentsWords (obj "out3.2") "g4++++i1"
    assertContentsWords (obj "out3.3") "g4++++i1"
    assertContentsWords (obj "out3.4") "g4+++s1+s2"

    run "-f../../src/Test/Ninja/test4.ninja out"
    assertExists $ obj "out.txt"
    assertExists $ obj "out2.txt"

    run "-f../../src/Test/Ninja/test5.ninja"
    assertExists $ obj "output file"

    writeFile (obj "nocreate.log") ""
    writeFile (obj "nocreate.in") ""
    run "-f../../src/Test/Ninja/nocreate.ninja"
    assertContentsWords (obj "nocreate.log") "x"
    run "-f../../src/Test/Ninja/nocreate.ninja"
    run "-f../../src/Test/Ninja/nocreate.ninja"
    assertContentsWords (obj "nocreate.log") "x x x"

    writeFile (obj "input") ""
    runFail "-f../../src/Test/Ninja/lint.ninja bad --lint" "'needed' file required rebuilding"
    run "-f../../src/Test/Ninja/lint.ninja good --lint"
    runFail "-f../../src/Test/Ninja/lint.ninja bad --lint" "not a pre-dependency"

    res <- fmap (drop 1 . lines . fst) $ captureOutput $ run "-f../../src/Test/Ninja/compdb.ninja -t compdb cxx @--no-report @--quiet"
    want <- lines <$> readFile "src/Test/Ninja/compdb.output"
    let eq a b | (a1,'*':a2) <- break (== '*') a = unless (a1 `isPrefixOf` b && a2 `isSuffixOf` b) $ a === b
               | otherwise = a === b
    length want === length res
    zipWithM_ eq want res

    -- Test initial variable bindings and variables in include/subninja statements
    let test6 = obj "test6"

    copyFile "src/Test/Ninja/test6-sub.ninja" $ test6 ++ "-sub.ninja"
    copyFile "src/Test/Ninja/test6-inc.ninja" $ test6 ++ "-inc.ninja"
    copyFile "src/Test/Ninja/test6.ninja" $ test6 ++ ".ninja"

    config <- Config.readConfigFileWithEnv [("v1", test6)] $ test6 ++ ".ninja"
    -- The file included by subninja should have a separate variable scope
    Map.lookup "v2" config === Just "g2"

    run "-f../../src/Test/Ninja/phonyorder.ninja bar.txt"

    -- tests from ninjasmith: https://github.com/ndmitchell/ninjasmith/
    run "-f../../src/Test/Ninja/redefine.ninja"
    assertContentsWords (obj "redefine.txt") "version3 version2"

    run "-f../../src/Test/Ninja/buildseparate.ninja"
    assertContentsWords (obj "buildseparate.txt") "XX"

    run "-f../../src/Test/Ninja/lexical.ninja"
    assertContentsWords (obj "lexical.txt") "XFoo_BarXXFooX.bar"

    when False $ do
        -- currently fails because Shake doesn't match Ninja here
        run "-f../../src/Test/Ninja/outputtouch.ninja"
        assertContentsWords (obj "outputtouch.txt") "hello"
        writeFile (obj "outputtouch.txt") "goodbye"
        run "-f../../src/Test/Ninja/outputtouch.ninja"
        assertContentsWords (obj "outputtouch.txt") "goodbye"
        removeFile (obj "outputtouch.txt")
        run "-f../../src/Test/Ninja/outputtouch.ninja"
        assertContentsWords (obj "outputtouch.txt") "hello"
