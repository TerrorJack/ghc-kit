{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE StrictData #-}

module Language.Haskell.GHC.Kit.Boot
  ( BootTask(..)
  , defaultBootTask
  , bootLib
  , boot
  ) where

import Control.Monad
import Data.Char
import qualified Language.Haskell.GHC.Kit.BuildInfo as P
import System.Directory
import System.Environment
import System.FilePath
import System.Process

data BootTask = BootTask
  { bootlibdir, topdir, pkgDb, ghc, ghcPkg :: FilePath
  , ghcOpts, confOpts :: [String]
  }

defaultBootTask :: IO BootTask
defaultBootTask = do
  pwd <- getCurrentDirectory
  pure
    BootTask
    { bootlibdir = pwd </> "boot-lib"
    , topdir = pwd </> ".boot"
    , pkgDb = pwd </> ".boot" </> "package.conf.d"
    , ghc = P.ghc
    , ghcPkg = P.ghcPkg
    , ghcOpts = []
    , confOpts = []
    }

bootLib :: BootTask -> IO ()
bootLib BootTask {..} = do
  callProcess P.ghc [bootlibdir </> "Setup.hs"]
  withCurrentDirectory bootlibdir $ do
    callProcess "./Setup" $
      ["configure", "--with-ghc=" ++ ghc] ++
      ["--ghc-options=" ++ opt | opt <- ghcOpts] ++
      [ "--builddir=" ++ (topdir </> "dist" </> bootlibdir)
      , "--package-db=" ++ pkgDb
      , "--prefix"
      , topdir
      ] ++
      confOpts
    callProcess
      "./Setup"
      ["build", "--builddir=" ++ (topdir </> "dist" </> bootlibdir)]
    callProcess
      "./Setup"
      ["install", "--builddir=" ++ (topdir </> "dist" </> bootlibdir)]
    when (bootlibdir == "ghc-prim") $
      callCommand $
      "sed -i -e 's,^exposed-modules:,exposed-modules: GHC.Prim,' " ++
      (pkgDb </> "ghc-prim-*.conf")
    callProcess ghcPkg ["--package-db", pkgDb, "recache"]

boot :: BootTask -> IO ()
boot bt@BootTask {..} = do
  unsetEnv "GHC_PACKAGE_PATH"
  withCurrentDirectory (bootlibdir </> "integer-gmp") $
    copyFile ("gmp" </> "ghc-gmp.h") ("include" </> "ghc-gmp.h")
  createDirectoryIfMissing True pkgDb
  ghclibdir <-
    takeWhile (not . isSpace) <$> readProcess ghc ["--print-libdir"] ""
  copyFile
    (ghclibdir </> "package.conf.d" </> "rts.conf")
    (pkgDb </> "rts.conf")
  callProcess ghcPkg ["--package-db", pkgDb, "recache"]
  withCurrentDirectory bootlibdir $ do
    bootLib bt {bootlibdir = "ghc-prim"}
    bootLib bt {bootlibdir = "integer-gmp"}
    bootLib bt {bootlibdir = "base", confOpts = "-finteger-gmp" : confOpts}
