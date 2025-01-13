module Ast.Parser.Utils where

import qualified Ast.Parser.State as PS
import qualified Ast.Types as AT
import qualified Control.Monad.Combinators.Expr as CE
import qualified Control.Monad.State as S
import qualified Text.Megaparsec as M
import qualified Text.Megaparsec.Char as MC
import qualified Text.Megaparsec.Char.Lexer as ML
import qualified Text.Megaparsec.Pos as MP

-- | A type alias for the parser, based on `Parsec` with `Void` error type and `String` input.
type Parser = M.ParsecT ParseErrorCustom String (S.StateT PS.ParserState IO)

data ParseErrorCustom
  = UnknownType String
  | InvalidFunctionType String AT.Type
  | InvalidDefer AT.Expr
  deriving (Show, Ord, Eq)

instance M.ShowErrorComponent ParseErrorCustom where
  showErrorComponent (UnknownType n) =
    "Unknown type: type \"" ++ n ++ "\" does not exist"
  showErrorComponent (InvalidFunctionType n t) =
    "Invalid Function Type: function \"" ++ n ++ "\" with type \"" ++ show t ++ "\" is not valid"
  showErrorComponent (InvalidDefer e) =
    "Invalid Defer: defer \"" ++ show e ++ "\" is not valid "

-- | Skips whitespace and comments (starting with `%`). Ensures proper handling of spacing in parsers.
sc :: Parser ()
sc = ML.space MC.space1 (ML.skipLineComment "%") $ ML.skipBlockComment "%%" "%%"

-- | Wraps a parser to consume trailing whitespace, returning the result of the inner parser.
lexeme :: Parser a -> Parser a
lexeme = ML.lexeme sc

-- | Parses a specific symbol (e.g., "+", "-") while skipping trailing whitespace.
symbol :: String -> Parser String
symbol = ML.symbol sc

-- | Tries each parser in the list sequentially, allowing backtracking for all but the last parser.
triedChoice :: [Parser a] -> Parser a
triedChoice ps =
  let triedPs = map M.try (init ps) ++ [last ps]
   in M.choice triedPs

-- | An identifier in our language syntax
identifier :: Parser String
identifier = lexeme ((:) <$> (MC.letterChar M.<|> M.oneOf "$_") <*> M.many (MC.alphaNumChar M.<|> M.oneOf "$_"))

-- | Gets the SrcLoc
parseSrcLoc :: Parser AT.SrcLoc
parseSrcLoc = do
  (MP.SourcePos {MP.sourceName = _sourceName, MP.sourceLine = _sourceLine, MP.sourceColumn = _sourceColumn}) <- M.getSourcePos
  return $ AT.SrcLoc {AT.srcFile = _sourceName, AT.srcLine = MP.unPos _sourceLine, AT.srcCol = MP.unPos _sourceColumn}

prefix :: String -> (AT.SrcLoc -> AT.Expr -> AT.Expr) -> CE.Operator Parser AT.Expr
prefix name f = CE.Prefix (f <$> (parseSrcLoc <* symbol name))

postfix :: String -> (AT.SrcLoc -> AT.Expr -> AT.Expr) -> CE.Operator Parser AT.Expr
postfix name f = CE.Postfix (f <$> (parseSrcLoc <* symbol name))

-- | Helper functions to define operators
binary :: String -> (AT.SrcLoc -> AT.Expr -> AT.Expr -> AT.Expr) -> CE.Operator Parser AT.Expr
binary name f = CE.InfixL (f <$> (parseSrcLoc <* symbol name))
