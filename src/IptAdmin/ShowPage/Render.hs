{-# LANGUAGE OverloadedStrings #-}

module IptAdmin.ShowPage.Render where

import Data.Monoid
import Data.String
import IptAdmin.Render
import IptAdmin.Types
import IptAdmin.Utils
import Iptables.Print
import Iptables.Types
import Text.Blaze
import qualified Text.Blaze.Html5 as H
import qualified Text.Blaze.Html5.Attributes as A

isModule :: RuleOption -> Bool
isModule (OModule _) = True
isModule _ = False

isOption :: RuleOption -> Bool
isOption = not . isModule

renderTable :: (String, String)       -- ^ (table name, table name for rendering)
            -> CountersType           -- ^ display bytes or packets counters
            -> Integer                -- ^ Max counter diff
            -> String                 -- ^ random string for 'refresh' link
            -> [Chain]                -- ^ table's chains
            -> [Chain]                -- ^ chains with relative start counters state
            -> Html
renderTable (tableName, _) countType maxCounter refreshString chains chains' = do
    mapM_ (renderChain tableName countType maxCounter refreshString) $ zip chains chains'
    H.a ! A.href (fromString $ "/addchain?table="++tableName) $ "Add chain"

-- | Table name -> counters type -> max counter -> refresh string ->  Chain -> Html
renderChain :: String -> CountersType -> Integer -> String -> (Chain,Chain) -> Html
renderChain tableName countType maxCounterDiff refreshString (Chain n p counters rs, Chain _ _ counters' rs') =
    H.table ! A.class_ "rules" $ do
        H.tr $ do
            H.td ! A.colspan "4" $
                H.div ! A.id "chainName" $ do
                    H.a ! A.name (fromString $ "chain" ++ "_" ++ n) $ fromString n
                    " "
                    H.a ! A.href (fromString $ "/show?table=" ++ tableName ++ "&refresh=" ++ refreshString ++ bookmarkForJump n Nothing)
                        ! A.title "Refresh page"
                        $ "↻"
            H.td ! A.class_ "rightAlign" ! A.colspan "3" $
                case p of
                    PUNDEFINED -> do
                        H.a ! A.class_ "button"
                            ! A.title "Delete chain"
                            ! A.href (fromString $ "/delchain?table="++tableName++"&chain="++n)
                            $ "X"
                        H.a ! A.class_ "button"
                            ! A.title "Edit chain name"
                            ! A.href (fromString $ "/editchain?table="++tableName++"&chain="++n)
                            $ "e"
                    a -> do
                        "Policy: "
                        H.a ! A.href (fromString $ "/editpolicy?table="++tableName++"&chain="++n) $
                            fromString $ show a
                        " "
                        case countType of
                            CTBytes -> do
                                H.a ! A.href (fromString $ "/show?table=" ++ tableName ++ "&countersType=packets" ++ bookmarkForJump n Nothing)
                                    $ "Bytes: "
                                fromString $ show $ cBytes counters
                            CTPackets -> do
                                H.a ! A.href (fromString $ "/show?table=" ++ tableName ++ "&countersType=bytes" ++ bookmarkForJump n Nothing)
                                    $ "Packets: "
                                H.span ! A.style "color:#000000;background-color:rgb(1,100,200)" $
                                    fromString $ show $ (cPackets counters - cPackets counters')
        H.tr $ do
            H.th ! A.class_ "col0" $
                case countType of
                    CTPackets -> do
                        H.span ! A.title "Packets" $
                            H.a ! A.href (fromString $ "/show?table=" ++ tableName ++ "&countersType=bytes" ++ bookmarkForJump n Nothing)
                                $ "P"
                        H.form ! A.id "resetForm" ! A.method "post" $ do
                            H.input ! A.type_ "hidden"
                                    ! A.name "table"
                                    ! A.value (fromString tableName)
                            H.input ! A.type_ "hidden"
                                    ! A.name "chain"
                                    ! A.value (fromString n)
                            H.input ! A.type_ "hidden"
                                    ! A.name "action"
                                    ! A.value "reset"
                            H.input ! A.title "Reset packets counters"
                                    ! A.id "submit"
                                    ! A.name "reset"
                                    ! A.type_ "submit"
                                    ! A.value "r"
                    CTBytes -> H.span ! A.title "Bytes" $
                        H.a ! A.href (fromString $ "/show?table=" ++ tableName ++ "&countersType=packets" ++ bookmarkForJump n Nothing)
                            $ "B"
            H.th ! A.class_ "col1" $ "#"
            H.th ! A.class_ "col2" $ "Modules"
            H.th ! A.class_ "col3" $ "Options"
            H.th ! A.class_ "col4" $ "Target"
            H.th ! A.class_ "col5" $ "Target params"
            H.th ! A.class_ "col6" $ ""
        mapM_ (renderRule (tableName, n) countType) $ zip [1..] $ zip rs rs'
        H.tr $
            H.td ! A.colspan "6" $
                H.a ! A.href (fromString $ "/add?table="++tableName++"&chain="++n) $ "Add rule"

-- | (Table name, Chain name) -> Rule -> Html
renderRule :: (String, String) -> CountersType -> (Int, (Rule, Rule)) -> Html
renderRule (tableName, chainName) countType (ruleNum, (Rule counters opts tar, Rule counters2 _ _)) =
    let mainTr = if even ruleNum then H.tr ! A.class_ "even"
                                 else H.tr
        mods' = filter isModule opts
        opts' = filter isOption opts
        mods'' = unwords $ map printOption mods'
        opts'' = unwords $ map printOption opts'
        (target', targetParam) = renderTarget tar
        ruleEditable = tarEditable && optsEditable
        tarEditable = case tar of
            TUnknown _ _ -> False
            _ -> True
        optsEditable = all optEditable opts
        optEditable opt = case opt of
            OProtocol _ _ -> True
            OSource _ _ -> True
            ODest _ _ -> True
            OInInt _ _ -> True
            OOutInt _ _ -> True
            OState _ -> True
            OSourcePort _ _ -> True
            ODestPort _ _ -> True
            OModule _ -> True
            _ -> False
        counters' = case countType of
            CTBytes -> fromString $ show $ cBytes counters
            CTPackets -> fromString $ show $ cPackets counters - cPackets counters2
    in
    mainTr $ do
        H.td counters'
        H.td $
            H.a ! A.name (fromString $ chainName ++ "_" ++ show ruleNum)
                $ fromString $ show ruleNum
        H.td $ fromString mods''
        H.td $ fromString opts''
        H.td target'
        H.td targetParam
        H.td $ do
            H.a ! A.class_ "button"
                ! A.title "Delete Rule"
                ! A.href (fromString $ "/del?table="++tableName++"&chain="++chainName++"&pos=" ++ show ruleNum)
                $ "X"
            if ruleEditable then
                H.a ! A.class_ "button"
                    ! A.title "Edit Rule"
                    ! A.href (fromString $ "/edit?table="++tableName++"&chain="++chainName++"&pos=" ++ show ruleNum)
                    $ "e"
                            else
                mempty
            H.a ! A.class_ "button"
                ! A.title "Insert Rule"
                ! A.href (fromString $ "/insert?table="++tableName++"&chain="++chainName++"&pos=" ++ show ruleNum)
                $ "+"
