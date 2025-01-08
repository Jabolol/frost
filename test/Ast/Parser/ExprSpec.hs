module Ast.Parser.ExprSpec (spec) where

import qualified Ast.Parser.Env as E
import qualified Ast.Parser.Expr as PE
import qualified Ast.Types as AT
import qualified Control.Monad.State as S
import Test.Hspec
import qualified Text.Megaparsec as M

spec :: Spec
spec = do
  let initialEnv = E.emptyEnv
  let parseWithEnv input =
        fst $ S.runState (M.runParserT PE.parseExpr "" input) initialEnv

  describe "parseExpr" $ do
    it "parses a literal expression" $ do
      let input = "123"
      let result = normalizeExpr <$> parseWithEnv input
      let expected = Right (AT.Lit normalizeLoc (AT.LInt 123))
      result `shouldBe` expected

    it "parses a variable expression" $
      do
        let input = "x"
        let env = E.insertVar "x" (AT.TInt 32) initialEnv
        let result = normalizeExpr <$> fst (S.runState (M.runParserT PE.parseExpr "" input) env)
        let expected = Right (AT.Var normalizeLoc "x" (AT.TInt 32))
        result `shouldBe` expected

    it "fails for an undefined variable" $ do
      let input = "y"
      let result = parseWithEnv input
      case result of
        Left _ -> True `shouldBe` True
        _ -> error "Expected failure"

    it "parses a function declaration" $ do
      let input = "add: (int int) -> (int) = x y { return 1 }"
      let expected =
            Right $
              AT.Function
                normalizeLoc
                "add"
                (AT.TFunction (AT.TInt 32) [AT.TInt 32, AT.TInt 32] False)
                ["x", "y"]
                (AT.Block [AT.Return normalizeLoc (Just (AT.Lit normalizeLoc (AT.LInt 1)))])
      let result = normalizeExpr <$> parseWithEnv input
      result `shouldBe` expected

    it "parses fibonacci" $ do
      let input = "add: (int int) -> (int) = x y { return 1 }"
      let result = normalizeExpr <$> parseWithEnv input
      let expected =
            AT.Function
              normalizeLoc
              "add"
              (AT.TFunction {AT.returnType = AT.TInt 32, AT.paramTypes = [AT.TInt 32, AT.TInt 32], AT.isVariadic = False})
              ["x", "y"]
              (AT.Block [AT.Return normalizeLoc (Just (AT.Lit normalizeLoc (AT.LInt 1)))])
      result `shouldBe` Right expected

    it "parses a variable declaration with initialization" $
      do
        let input = "x : int = 42"
        let result = normalizeExpr <$> parseWithEnv input
        let expected =
              Right
                AT.Declaration
                  { AT.declLoc = AT.SrcLoc "" 0 0,
                    AT.declName = "x",
                    AT.declType = AT.TInt 32,
                    AT.declInit = Just (AT.Lit (AT.SrcLoc "" 0 00) (AT.LInt 42))
                  }
        result `shouldBe` expected

    it "parses an assignment expression" $ do
      let input = "x = 42"
      let env = E.insertVar "x" (AT.TInt 0) initialEnv
      let result = normalizeExpr <$> fst (S.runState (M.runParserT PE.parseExpr "" input) env)
      let expected = Right (AT.Assignment normalizeLoc (AT.Var normalizeLoc "x" (AT.TInt 0)) (AT.Lit normalizeLoc (AT.LInt 42)))
      result `shouldBe` expected

    it "parses a function call" $ do
      let env = E.insertVar "foo" (AT.TFunction {AT.returnType = AT.TVoid, AT.paramTypes = [AT.TInt 0], AT.isVariadic = False}) initialEnv
      let input = "foo(123)"
      normalizeExpr <$> fst (S.runState (M.runParserT PE.parseExpr "" input) env)
        `shouldBe` Right
          (AT.Call normalizeLoc (AT.Var normalizeLoc "foo" (AT.TFunction {AT.returnType = AT.TVoid, AT.paramTypes = [AT.TInt 0], AT.isVariadic = False})) [AT.Lit normalizeLoc (AT.LInt 123)])

    it "parses an if-else expression" $ do
      let input = "if x { return 1 } else { return 0 }"
      let env = E.insertVar "x" AT.TBoolean initialEnv
      let result = normalizeExpr <$> fst (S.runState (M.runParserT PE.parseExpr "" input) env)
      let expected =
            Right $
              AT.If
                normalizeLoc
                (AT.Var normalizeLoc "x" AT.TBoolean)
                (AT.Block [AT.Return normalizeLoc (Just (AT.Lit normalizeLoc (AT.LInt 1)))])
                (Just (AT.Block [AT.Return normalizeLoc (Just (AT.Lit normalizeLoc (AT.LInt 0)))]))

      result `shouldBe` expected

    it "parses an if-else expression with implicit returns" $ do
      let input = "main: (void) -> (void) = { if x { 1 } else { 0 } }"
      let env = E.insertVar "x" AT.TBoolean initialEnv
      let result = normalizeExpr <$> fst (S.runState (M.runParserT PE.parseExpr "" input) env)
      let expected =
            Right $
              AT.Function
                normalizeLoc
                "main"
                (AT.TFunction AT.TVoid [AT.TVoid] False)
                []
                ( AT.Block
                    [ AT.If
                        normalizeLoc
                        (AT.Var normalizeLoc "x" AT.TBoolean)
                        (AT.Block [AT.Return normalizeLoc (Just (AT.Lit normalizeLoc (AT.LInt 1)))])
                        (Just (AT.Block [AT.Return normalizeLoc (Just (AT.Lit normalizeLoc (AT.LInt 0)))]))
                    ]
                )

      result `shouldBe` expected

    it "parses a while loop" $ do
      let input = "loop z { z = 0 }"
      let env = E.insertVar "z" (AT.TInt 32) initialEnv
      let result = normalizeExpr <$> fst (S.runState (M.runParserT PE.parseExpr "" input) env)
      let expected =
            Right $
              AT.While
                normalizeLoc
                ( AT.Var
                    normalizeLoc
                    "z"
                    (AT.TInt 32)
                )
                ( AT.Block
                    [ AT.Assignment
                        normalizeLoc
                        (AT.Var normalizeLoc "z" (AT.TInt 32))
                        (AT.Lit normalizeLoc (AT.LInt 0))
                    ]
                )
      result `shouldBe` expected

    it "parses a for loop" $ do
      let input = "from 0 to 10 by 2 |i: int| { i = 0 }"
      let env = E.emptyEnv
      let result = normalizeExpr <$> fst (S.runState (M.runParserT PE.parseExpr "" input) env)
      let expected =
            Right $
              AT.For
                { AT.forLoc = normalizeLoc,
                  AT.forInit =
                    AT.Declaration
                      normalizeLoc
                      "i"
                      (AT.TInt 32)
                      (Just (AT.Lit normalizeLoc (AT.LInt 0))),
                  AT.forCond =
                    AT.Op
                      normalizeLoc
                      AT.Lt
                      (AT.Var normalizeLoc "i" (AT.TInt 32))
                      (AT.Lit normalizeLoc (AT.LInt 10)),
                  AT.forStep =
                    AT.Assignment
                      normalizeLoc
                      (AT.Var normalizeLoc "i" (AT.TInt 32))
                      ( AT.Op
                          normalizeLoc
                          AT.Add
                          (AT.Var normalizeLoc "i" (AT.TInt 32))
                          (AT.Lit normalizeLoc (AT.LInt 2))
                      ),
                  AT.forBody =
                    AT.Block
                      [ AT.Assignment
                          normalizeLoc
                          (AT.Var normalizeLoc "i" (AT.TInt 32))
                          ( AT.Lit normalizeLoc (AT.LInt 0)
                          )
                      ]
                }
      result `shouldBe` expected

    it "parses a for loop with a dynamic range" $ do
      let input = "from 0 to 10 by x |i: int| { i = 0 }"
      let env = E.insertVar "x" (AT.TInt 32) E.emptyEnv
      let result = normalizeExpr <$> fst (S.runState (M.runParserT PE.parseExpr "" input) env)
      let expected =
            Right $
              AT.For
                { AT.forLoc = normalizeLoc,
                  AT.forInit =
                    AT.Declaration
                      normalizeLoc
                      "i"
                      (AT.TInt 32)
                      (Just (AT.Lit normalizeLoc (AT.LInt 0))),
                  AT.forCond =
                    AT.Op
                      normalizeLoc
                      AT.Lt
                      (AT.Var normalizeLoc "i" (AT.TInt 32))
                      (AT.Lit normalizeLoc (AT.LInt 10)),
                  AT.forStep =
                    AT.Assignment
                      normalizeLoc
                      (AT.Var normalizeLoc "i" (AT.TInt 32))
                      ( AT.Op
                          normalizeLoc
                          AT.Add
                          (AT.Var normalizeLoc "i" (AT.TInt 32))
                          (AT.Var normalizeLoc "x" (AT.TInt 32))
                      ),
                  AT.forBody =
                    AT.Block
                      [ AT.Assignment
                          normalizeLoc
                          (AT.Var normalizeLoc "i" (AT.TInt 32))
                          ( AT.Lit normalizeLoc (AT.LInt 0)
                          )
                      ]
                }
      result `shouldBe` expected

    it "parses a break statement" $ do
      let input = "stop"
      let result = normalizeExpr <$> parseWithEnv input
      let expected = Right (AT.Break normalizeLoc)
      result `shouldBe` expected

    it "parses a continue statement" $ do
      let input = "next"
      let result = normalizeExpr <$> parseWithEnv input
      let expected = Right (AT.Continue normalizeLoc)
      result `shouldBe` expected

    it "parses a struct access" $ do
      let input = "myStruct.myField"
      let structType = AT.TStruct "Custom" [("myField", AT.TChar)]
      let env = E.insertVar "myStruct" structType $ E.insertType "Custom" structType E.emptyEnv
      let result = normalizeExpr <$> fst (S.runState (M.runParserT PE.parseExpr "" input) env)
      let expected =
            Right $
              AT.StructAccess
                normalizeLoc
                (AT.Var normalizeLoc "myStruct" structType)
                "myField"
      result `shouldBe` expected

    it "parses a nested struct access" $ do
      let input = "myStruct.innerStruct.field"
      let structType = AT.TStruct "Custom" [("innerStruct", AT.TStruct "InnerCustom" [("field", AT.TChar)])]
      let env = E.insertVar "myStruct" structType $ E.insertType "Custom" structType E.emptyEnv
      let result = normalizeExpr <$> fst (S.runState (M.runParserT PE.parseExpr "" input) env)
      let expected =
            Right $
              AT.StructAccess
                normalizeLoc
                ( AT.StructAccess
                    normalizeLoc
                    (AT.Var normalizeLoc "myStruct" structType)
                    "innerStruct"
                )
                "field"
      result `shouldBe` expected

    it "parses an array access" $ do
      let input = "myArray.1"
      let arrayType = AT.TArray AT.TChar Nothing
      let env = E.insertVar "myArray" arrayType E.emptyEnv
      let result = normalizeExpr <$> fst (S.runState (M.runParserT PE.parseExpr "" input) env)
      let expected =
            Right $
              AT.ArrayAccess
                normalizeLoc
                (AT.Var normalizeLoc "myArray" arrayType)
                (AT.Lit normalizeLoc $ AT.LInt 1)
      result `shouldBe` expected

    it "parses an nested array access" $ do
      let input = "myArray.1.1"
      let arrayType = AT.TArray (AT.TArray AT.TChar Nothing) Nothing
      let env = E.insertVar "myArray" arrayType E.emptyEnv
      let result = normalizeExpr <$> fst (S.runState (M.runParserT PE.parseExpr "" input) env)
      let expected =
            Right $
              AT.ArrayAccess
                normalizeLoc
                ( AT.ArrayAccess
                    normalizeLoc
                    (AT.Var normalizeLoc "myArray" arrayType)
                    (AT.Lit normalizeLoc $ AT.LInt 1)
                )
                (AT.Lit normalizeLoc $ AT.LInt 1)
      result `shouldBe` expected

    it "parses an type cast" $ do
      let input = "@int('a')"
      let result = normalizeExpr <$> parseWithEnv input
      let expected =
            Right $
              AT.Cast
                normalizeLoc
                (AT.TInt 32)
                (AT.Lit normalizeLoc $ AT.LChar 'a')
      result `shouldBe` expected

    it "parses an operator" $ do
      let input = "1 + 1"
      let result = normalizeExpr <$> parseWithEnv input
      let expected =
            Right $
              AT.Op
                normalizeLoc
                AT.Add
                (AT.Lit normalizeLoc $ AT.LInt 1)
                (AT.Lit normalizeLoc $ AT.LInt 1)
      result `shouldBe` expected

    it "parses an operator with hierarchy" $ do
      let input = "1 + 1 * 2"
      let result = normalizeExpr <$> parseWithEnv input
      let expected =
            Right $
              AT.Op
                normalizeLoc
                AT.Mul
                ( AT.Op
                    normalizeLoc
                    AT.Add
                    (AT.Lit normalizeLoc $ AT.LInt 1)
                    (AT.Lit normalizeLoc $ AT.LInt 1)
                )
                (AT.Lit normalizeLoc $ AT.LInt 2)
      result `shouldBe` expected

    it "parses a unary operator" $ do
      let input = "not 1"
      let result = normalizeExpr <$> parseWithEnv input
      let expected =
            Right $
              AT.UnaryOp
                normalizeLoc
                AT.Not
                (AT.Lit normalizeLoc $ AT.LInt 1)
      result `shouldBe` expected

normalizeLoc :: AT.SrcLoc
normalizeLoc = AT.SrcLoc "" 0 0

normalizeExpr :: AT.Expr -> AT.Expr
normalizeExpr (AT.Lit _ lit) = AT.Lit normalizeLoc lit
normalizeExpr (AT.Var _ name t) = AT.Var normalizeLoc name t
normalizeExpr (AT.Function _ name t params body) = AT.Function normalizeLoc name t params (normalizeExpr body)
normalizeExpr (AT.Declaration _ name t initVal) = AT.Declaration normalizeLoc name t (fmap normalizeExpr initVal)
normalizeExpr (AT.Assignment _ target value) = AT.Assignment normalizeLoc (normalizeExpr target) (normalizeExpr value)
normalizeExpr (AT.Call _ func args) = AT.Call normalizeLoc (normalizeExpr func) (map normalizeExpr args)
normalizeExpr (AT.If _ cond thenBranch elseBranch) = AT.If normalizeLoc (normalizeExpr cond) (normalizeExpr thenBranch) (fmap normalizeExpr elseBranch)
normalizeExpr (AT.Block exprs) = AT.Block (map normalizeExpr exprs)
normalizeExpr (AT.Return _ value) = AT.Return normalizeLoc (fmap normalizeExpr value)
normalizeExpr (AT.Op _ op e1 e2) = AT.Op normalizeLoc op (normalizeExpr e1) (normalizeExpr e2)
normalizeExpr (AT.UnaryOp _ op e) = AT.UnaryOp normalizeLoc op (normalizeExpr e)
normalizeExpr (AT.For _ i c s b) = AT.For normalizeLoc (normalizeExpr i) (normalizeExpr c) (normalizeExpr s) (normalizeExpr b)
normalizeExpr (AT.While _ c b) = AT.While normalizeLoc (normalizeExpr c) (normalizeExpr b)
normalizeExpr (AT.Continue _) = AT.Continue normalizeLoc
normalizeExpr (AT.Break _) = AT.Break normalizeLoc
normalizeExpr (AT.StructAccess _ e s) = AT.StructAccess normalizeLoc (normalizeExpr e) s
normalizeExpr (AT.ArrayAccess _ e1 e2) = AT.ArrayAccess normalizeLoc (normalizeExpr e1) (normalizeExpr e2)
normalizeExpr (AT.Cast _ t e) = AT.Cast normalizeLoc t (normalizeExpr e)
