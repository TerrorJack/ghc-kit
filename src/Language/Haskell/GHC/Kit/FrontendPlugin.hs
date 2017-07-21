{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE StrictData #-}

module Language.Haskell.GHC.Kit.FrontendPlugin
  ( frontendPlugin
  ) where

import Control.Monad.IO.Class
import Data.Functor
import GHC
import GhcPlugins
import Hooks
import Language.Haskell.GHC.Kit.RunPhase (runPhaseWith)
import Language.Haskell.GHC.Kit.WalkAST
import Language.Haskell.GHC.Kit.WithIRs

coreAction :: ModSummary -> IR -> IO ()
coreAction ModSummary {..} IR {core = CgGuts {..}} = do
  putStrLn $ "Current Module: " ++ showSDocUnsafe (ppr ms_mod)
  let bs = do
        b <- cg_binds
        case b of
          NonRec v _ -> [v]
          Rec bs' -> [v | (v, _) <- bs']
  putStrLn $ "Top-level Binding Modules: " ++ showSDocUnsafe (ppr (extmods bs))
  let ms = extmods cg_binds
  putStrLn $ "Dependent Modules: " ++ showSDocUnsafe (ppr ms)

frontendAction :: [String] -> [(String, Maybe Phase)] -> Ghc ()
frontendAction args targets = do
  liftIO $ putStrLn $ "args: " ++ show args
  dflags <- getSessionDynFlags
  rp <- liftIO $ toRunPhase coreAction
  void $
    setSessionDynFlags
      dflags
      { ghcMode = CompManager
      , hooks = emptyHooks {runPhaseHook = Just $ runPhaseWith rp}
      }
  sequenceA [guessTarget t f | (t, f) <- targets] >>= setTargets
  sf <- load LoadAllTargets
  case sf of
    Succeeded -> pure ()
    Failed -> fail "GHC.load returned Failed."

frontendPlugin :: FrontendPlugin
frontendPlugin = defaultFrontendPlugin {frontend = frontendAction}