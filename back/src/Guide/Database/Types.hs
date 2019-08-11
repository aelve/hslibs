{-# LANGUAGE DataKinds         #-}
{-# LANGUAGE TemplateHaskell   #-}
{-# LANGUAGE OverloadedLabels  #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes       #-}
{-# LANGUAGE TypeOperators     #-}

-- | Types for postgres database
module Guide.Database.Types
       (
       -- * Types
         DatabaseError(..)
       , CategoryRow (..)
       , ItemRow (..)
       , TraitRow (..)
       -- ** Lenses
       , CategoryRowLenses (..)
       , ItemRowLenses (..)
       , TraitRowLenses (..)

       -- * Type convertions
       , categoryRowToCategory
       , categoryToRowCategory
       , itemRowToItem
       , itemToRowItem
       , traitRowToTrait
       , traitToTraitRow

       ) where

import Imports

import Named

import Guide.Markdown (toMarkdownBlock, toMarkdownTree, toMarkdownInline)
import Guide.Types.Core (Category (..), CategoryStatus, Item (..), ItemSection, Trait (..),
                         TraitType)
import Guide.Utils (Uid (..), makeClassWithLenses, fields)


-- | Custom datatype errors for database
data DatabaseError
  = ItemNotFound (Uid Item)
  | CategoryNotFound (Uid Category)
  | TraitNotFound (Uid Trait)
  | CategoryRowUpdateNotAllowed
      { deCategoryId :: Uid Category
      , deFieldName :: Text }
  | ItemRowUpdateNotAllowed
      { deItemId :: Uid Item
      , deFieldName :: Text }
  | TraitRowUpdateNotAllowed
      { deTraitId :: Uid Trait
      , deFieldName :: Text }
  deriving Show

-- | Category intermediary type.
data CategoryRow = CategoryRow
  { categoryRowUid             :: Uid Category
  , categoryRowTitle           :: Text
  , categoryRowCreated         :: UTCTime
  , categoryRowGroup           :: Text
  , categoryRowStatus          :: CategoryStatus
  , categoryRowNotes           :: Text
  , categoryRowEnabledSections :: Set ItemSection
  , categoryRowItemsOrder      :: [Uid Item]
  } deriving Show

-- | Make CategoryRowLenses Class to use lenses with this type.
makeClassWithLenses ''CategoryRow

-- | Item intermediary type.
data ItemRow = ItemRow
  { itemRowUid         :: Uid Item
  , itemRowName        :: Text
  , itemRowCreated     :: UTCTime
  , itemRowLink        :: Maybe Text
  , itemRowHackage     :: Maybe Text
  , itemRowSummary     :: Text
  , itemRowEcosystem   :: Text
  , itemRowNotes       :: Text
  , itemRowDeleted     :: Bool
  , itemRowCategoryUid :: Uid Category
  , itemRowProsOrder   :: [Uid Trait]
  , itemRowConsOrder   :: [Uid Trait]
  } deriving Show

-- | Make ItemRowLenses Class to use lenses with this type.
makeClassWithLenses ''ItemRow

-- | Trait intermediary type.
data TraitRow = TraitRow
  { traitRowUid     :: Uid Trait
  , traitRowContent :: Text
  , traitRowDeleted :: Bool
  , traitRowType    :: TraitType
  , traitRowItemUid :: Uid Item
  } deriving Show

-- | Make TraitRowLenses Class to use lenses with this type.
makeClassWithLenses ''TraitRow

----------------------------------------------------------------------------
-- Convertions between types
----------------------------------------------------------------------------

-- | Convert CategoryRow to Category.
--
-- | To fetch items (they have an order) use 'getItemRowsByCategory' from 'Get' module.
-- | To fetch deleted items use 'getDeletedItemRowsByCategory' from 'Get' module
--
-- TODO: somehow handle the case when item IDs don't match the @itemsOrder@?
--
-- TODO: use 'fields' for pattern-matching.
categoryRowToCategory
  :: "items" :! [Item]
  -> "itemsDeleted" :! [Item]
  -> CategoryRow
  -> Category
categoryRowToCategory
  (arg #items -> items)
  (arg #itemsDeleted -> itemsDeleted)
  CategoryRow{..}
  =
  Category
    { categoryUid = categoryRowUid
    , categoryTitle = categoryRowTitle
    , categoryCreated = categoryRowCreated
    , categoryGroup = categoryRowGroup
    , categoryStatus = categoryRowStatus
    , categoryNotes = toMarkdownBlock categoryRowNotes
    , categoryItems = items
    , categoryItemsDeleted = itemsDeleted
    , categoryEnabledSections = categoryRowEnabledSections
    }

-- | Convert Category to CategoryRow.
categoryToRowCategory :: Category -> CategoryRow
categoryToRowCategory $(fields 'Category) = CategoryRow
  { categoryRowUid = categoryUid
  , categoryRowTitle = categoryTitle
  , categoryRowCreated = categoryCreated
  , categoryRowGroup = categoryGroup
  , categoryRowStatus = categoryStatus
  , categoryRowNotes = toText $ show categoryNotes -- TODO fix!
  , categoryRowEnabledSections = categoryEnabledSections
  , categoryRowItemsOrder = map itemUid categoryItems
  }
  where
    -- Ignored fields
    _ = categoryItemsDeleted

-- | Convert ItemRow to Item.
--
-- | To fetch traits (they have an order) use 'getTraitRowsByItem' from 'Get' module.
-- | To fetch deleted traits use 'getDeletedTraitRowsByItem' from 'Get' module
itemRowToItem
  :: "proTraits" :! [Trait]
  -> "proDeletedTraits" :! [Trait]
  -> "conTraits" :! [Trait]
  -> "conDeletedTraits" :! [Trait]
  -> ItemRow
  -> Item
itemRowToItem
  (arg #proTraits -> proTraits)
  (arg #proDeletedTraits -> proDeletedTraits)
  (arg #conTraits -> conTraits)
  (arg #conDeletedTraits -> conDeletedTraits)
  ItemRow{..}
  =
  Item
    { itemUid = itemRowUid
    , itemName = itemRowName
    , itemCreated = itemRowCreated
    , itemHackage = itemRowHackage
    , itemSummary = toMarkdownBlock itemRowSummary
    , itemPros = proTraits
    , itemProsDeleted = proDeletedTraits
    , itemCons = conTraits
    , itemConsDeleted = conDeletedTraits
    , itemEcosystem = toMarkdownBlock itemRowEcosystem
    , itemNotes = toMarkdownTree prefix itemRowNotes
    , itemLink = itemRowLink
    }
  where
    prefix = "item-notes-" <> uidToText itemRowUid <> "-"

-- | Convert Item to ItemRow.
itemToRowItem :: Uid Category -> "deleted" :! Bool -> Item -> ItemRow
itemToRowItem catId (arg #deleted -> deleted) $(fields 'Item) = ItemRow
  { itemRowUid = itemUid
  , itemRowName = itemName
  , itemRowCreated = itemCreated
  , itemRowLink = itemLink
  , itemRowHackage = itemHackage
  , itemRowSummary = toText $ show itemSummary -- TODO fix
  , itemRowEcosystem = toText $ show itemEcosystem -- TODO fix
  , itemRowNotes = toText $ show itemNotes -- TODO fix
  , itemRowDeleted = deleted
  , itemRowCategoryUid = catId
  , itemRowProsOrder = map traitUid itemPros
  , itemRowConsOrder = map traitUid itemCons
  }
  where
    -- Ignored fields
    _ = (itemConsDeleted, itemProsDeleted)

-- | Convert TraitRow to Trait.
traitRowToTrait :: TraitRow -> Trait
traitRowToTrait TraitRow{..} = Trait
  { traitUid = traitRowUid
  , traitContent = toMarkdownInline traitRowContent
  }

-- Convert Trait to TraitRow
traitToTraitRow
  :: Uid Item
  -> "deleted" :! Bool
  -> TraitType
  -> Trait
  -> TraitRow
traitToTraitRow itemId (arg #deleted -> deleted) traitType $(fields 'Trait) =
  TraitRow
    { traitRowUid = traitUid
    , traitRowContent = toText $ show traitContent  -- TODO fix
    , traitRowDeleted = deleted
    , traitRowType = traitType
    , traitRowItemUid = itemId
    }