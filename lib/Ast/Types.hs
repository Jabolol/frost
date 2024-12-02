module Ast.Types
  ( AST (..),
    Literal (..),
    Expr (..),
    Operation (..),
  )
where

-- | Literal values that can appear in the LISP AST.
data Literal
  = LInt Integer
  | LBool Bool
  | LSymbol String
  deriving (Show, Eq)

-- | Expression nodes in the LISP AST.
data Expr
  = Lit Literal
  | Var String
  | Define String Expr
  | Call Expr [Expr]
  | Lambda [String] Expr
  | If Expr Expr Expr
  | Op Operation Expr Expr
  deriving (Show, Eq)

-- | Operations supported by the language, such as addition, subtraction, etc.
data Operation
  = Add
  | Sub
  | Mult
  | Div
  | Lt
  | Gt
  | Lte
  | Gte
  | Equal
  | And
  | Or
  deriving (Show, Eq)

-- | Top-level AST representation for the program.
newtype AST = AST [Expr] deriving (Show, Eq)
