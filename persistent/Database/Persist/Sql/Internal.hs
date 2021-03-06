{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PatternGuards #-}
-- | Intended for creating new backends.
module Database.Persist.Sql.Internal
    ( mkColumns
    , defaultAttribute
    ) where

import Database.Persist.Types
import Database.Persist.Quasi
import Data.Char (isSpace)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Monoid (mappend, mconcat)
import Database.Persist.Sql.Types

defaultAttribute :: [Attr] -> Maybe Text
defaultAttribute [] = Nothing
defaultAttribute (a:as)
    | Just d <- T.stripPrefix "default=" a = Just d
    | otherwise = defaultAttribute as

-- | Create the list of columns for the given entity.
mkColumns :: [EntityDef] -> EntityDef -> ([Column], [UniqueDef], [ForeignDef])
mkColumns allDefs t =
    (cols, entityUniques t, entityForeigns t)
  where
    cols :: [Column]
    cols = map go (entityFields t)

    tn :: DBName
    tn = entityDB t

    go :: FieldDef -> Column
    go fd =
        Column
            (fieldDB fd)
            (nullable (fieldAttrs fd) /= NotNullable || entitySum t)
            (fieldSqlType fd)
            (defaultAttribute $ fieldAttrs fd)
            Nothing
            (maxLen $ fieldAttrs fd)
            (ref (fieldDB fd) (fieldReference fd) (fieldAttrs fd))

    maxLen :: [Attr] -> Maybe Integer
    maxLen [] = Nothing
    maxLen (a:as)
        | Just d <- T.stripPrefix "maxlen=" a =
            case reads (T.unpack d) of
              [(i, s)] | all isSpace s -> Just i
              _ -> error $ "Could not parse maxlen field with value " ++
                           show d ++ " on " ++ show tn
        | otherwise = maxLen as

    ref :: DBName
        -> ReferenceDef
        -> [Attr]
        -> Maybe (DBName, DBName) -- table name, constraint name
    ref c fe []
        | ForeignRef f _ <- fe =
            Just (resolveTableName allDefs f, refName tn c)
        | otherwise = Nothing
    ref _ _ ("noreference":_) = Nothing
    ref c _ (a:_)
        | Just x <- T.stripPrefix "reference=" a =
            Just (DBName x, refName tn c)
    ref c x (_:as) = ref c x as

refName :: DBName -> DBName -> DBName
refName (DBName table) (DBName column) =
    DBName $ Data.Monoid.mconcat [table, "_", column, "_fkey"]

resolveTableName :: [EntityDef] -> HaskellName -> DBName
resolveTableName [] (HaskellName hn) = error $ "Table not found: " `Data.Monoid.mappend` T.unpack hn
resolveTableName (e:es) hn
    | entityHaskell e == hn = entityDB e
    | otherwise = resolveTableName es hn
