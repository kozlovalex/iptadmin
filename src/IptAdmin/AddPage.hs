
module IptAdmin.AddPage where

import Control.Monad.Error
import Control.Monad.State
import Happstack.Server.SimpleHTTP
import IptAdmin.EditForm
import IptAdmin.EditForm.Class
import IptAdmin.EditForm.Render
import IptAdmin.EditForm.Utils
import IptAdmin.System
import IptAdmin.Types
import IptAdmin.Utils
import Iptables
import Iptables.Print
import Iptables.Types
import Text.Blaze.Renderer.Pretty (renderHtml)

pageHandlers :: IptAdmin Response
pageHandlers = msum [ methodSP GET pageHandlerGet
                    , methodSP POST pageHandlerPost
                    ]

pageHandlerGet :: IptAdmin Response
pageHandlerGet = do
    tableName <- getInputNonEmptyString "table"
    chainName <- getInputNonEmptyString "chain"

    table <- getTable tableName

    checkParams table chainName

    (PackedEditForm form) <- nullSelForm tableName chainName
    let userChainNames = getUserChains form chainName table
    return $ buildResponse $ renderHtml $ do
        editFormHtml (tableName, chainName, 0, userChainNames) form Nothing

pageHandlerPost :: IptAdmin Response
pageHandlerPost = do
    tableName <- getInputNonEmptyString "table"
    chainName <- getInputNonEmptyString "chain"

    table <- getTable tableName

    checkParams table chainName

    (PackedEditForm addFormParams) <- httpInputToSelForm tableName chainName
    let userChainNames = getUserChains addFormParams chainName table

    let checkResE = editPageProcessParams addFormParams
    case checkResE of
            Left formMes -> return $ buildResponse $ renderHtml $ do
                editFormHtml (tableName, chainName, 0, userChainNames) addFormParams $ Just formMes
            Right (options, target, formMes) -> do
                let (_, options') = runState (mapM_ completeModules options) options
                let rule = Rule (Counters 0 0) options' target

                submit <- getInputString "submit"
                case submit of
                    "Check" -> return $ buildResponse $ renderHtml (do
                        editFormHtml (tableName, chainName, 0, userChainNames) addFormParams $ Just formMes
                        ) -- ++ printRuleForRun rule
                    "Submit" -> do
                        tryChange (appendRule tableName chainName rule)
                        -- redir $ "/show?table=" ++ tableName ++ bookmarkForJump chainName Nothing
                        return $ buildResponse "ok"
                    a -> throwError $ "Wrong value for 'submit' parameter: " ++ a

checkParams :: [Chain] -> String -> IptAdmin ()
checkParams table chainName = do
    let chainMay = getChainByName chainName table
    _ <- maybe (throwError $ "Invalid chain name: " ++ chainName)
                   return
                   chainMay
    return ()
