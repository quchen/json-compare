{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ViewPatterns #-}

module JsonDiff
  ( diffStructures
  , JsonDiff
  ) where

import Data.Aeson (Value)
import qualified Data.Aeson as Json
import qualified Data.HashMap.Strict as Map
import Data.HashMap.Strict (HashMap)
import Data.Text.Prettyprint.Doc
import Protolude

type JsonPath = [JsonPathStep]

data JsonPathStep
  = Root -- ^ Root of the JSON document
  | Key Text -- ^ Key of an object
  | Ix Int -- ^ Index of an array
  deriving (Show)

data JsonDiff
  = KeyNotPresent JsonPath -- ^ the path to the object
                  Text -- ^ the key that was not found
  | NotFoundInArray JsonPath -- ^ the path to the array
                    Int -- ^ the index of the found element
                    JsonType -- ^ the type that was not found
  | WrongType JsonPath -- ^ the path to the JSON value
              JsonType -- ^ the type of the expected value
              JsonType -- ^ the type of the actual value
  deriving (Show)

data JsonType
  = Null
  | Bool
  | Number
  | String
  | Object
  | Array
  deriving (Eq, Enum, Bounded, Show)

instance Pretty JsonPathStep where
    pretty step = case step of
        Root  -> "$"
        Key k -> pretty k
        Ix i  -> pretty i
    prettyList = concatWith (surround ".") . map pretty . reverse

instance Pretty JsonType

instance Pretty JsonDiff where
    pretty diff = case diff of
        KeyNotPresent path key -> appendPath path $
            "Expected key:" <+> pretty key
        NotFoundInArray path index ty -> appendPath path $
            "Expected type" <+> squotes (pretty ty)
            <+> "for index" <+> squotes (pretty index)
        WrongType path expectedTy actualTy -> appendPath path $
            "Expected type" <+> squotes (pretty expectedTy)
            <> ", but the actual data had type" <+> squotes (pretty actualTy)
      where
        appendPath path x = nest 4 (vsep [x, "at path: " <+> pretty path])

    prettyList = vsep . map pretty

-- | @diffStructures expected actual@ compares the structures of the two JSON values and reports each item in @actual@ that is not present in @expected@
-- if @actual@ is a strict subset (or sub-object) of @expected@, the list should be null
--
diffStructures ::
     Value -- ^ expected
  -> Value -- ^ actual
  -> [JsonDiff] -- ^ differences from actual to expected
diffStructures expected actual = diffStructureAtPath [Root] expected actual

diffStructureAtPath :: JsonPath -> Value -> Value -> [JsonDiff]
diffStructureAtPath _ _ Json.Null = []
    -- null is a valid subset of any JSON
diffStructureAtPath _ (Json.Bool _) (Json.Bool _) = []
diffStructureAtPath _ (Json.Number _) (Json.Number _) = []
diffStructureAtPath _ (Json.String _) (Json.String _) = []
diffStructureAtPath path (Json.Object expected) (Json.Object actual) =
  concatMap (diffObjectWithEntry path expected) (Map.toList actual)
diffStructureAtPath path (Json.Array expected) (Json.Array actual) =
  concatMap (diffArrayWithElement path (toList expected)) (toIndexedList actual)
diffStructureAtPath path a b = [WrongType path (toType a) (toType b)]

diffObjectWithEntry ::
     JsonPath -> HashMap Text Value -> (Text, Value) -> [JsonDiff]
diffObjectWithEntry path expected (k, vActual) =
  case Map.lookup k expected of
    Just vExpected -> diffStructureAtPath (Key k : path) vExpected vActual
    Nothing -> [KeyNotPresent path k]

diffArrayWithElement :: JsonPath -> [Value] -> (Int, Value) -> [JsonDiff]
diffArrayWithElement path expected (n, actual) =
  case filter (sameType actual) expected of
    [] -> [NotFoundInArray path n (toType actual)]
    xs ->
      minimumBy (comparing length) $
      map (\x -> diffStructureAtPath (Ix n : path) x actual) xs

toIndexedList :: Foldable l => l a -> [(Int, a)]
toIndexedList = zip [0 ..] . toList

sameType :: Value -> Value -> Bool
sameType = (==) `on` toType

toType :: Value -> JsonType
toType Json.Null = Null
toType (Json.Bool _) = Bool
toType (Json.Number _) = Number
toType (Json.String _) = String
toType (Json.Object _) = Object
toType (Json.Array _) = Array
