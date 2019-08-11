{-# LANGUAGE DeriveDataTypeable  #-}
{-# LANGUAGE FlexibleContexts    #-}
{-# LANGUAGE FlexibleInstances   #-}
{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE QuasiQuotes         #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeFamilies        #-}
{-# LANGUAGE TemplateHaskell     #-}


-- | Core types for content.
--
-- The whole site is a list of categories ('Category'). Categories have
-- items ('Item') in them. Items have some sections (fields inside of
-- 'Item'), as well as traits ('Trait').
module Guide.Types.Core
(
  Trait(..),
  TraitLenses(..),
  TraitType (..),
  ItemKind(..),
    hackageName,
  ItemSection(..),
  Item(..),
  ItemLenses(..),
  CategoryStatus(..),
  Category(..),
  CategoryLenses(..),
  categorySlug,
)
where


import Imports

-- acid-state
import Data.SafeCopy hiding (kind)
import Data.SafeCopy.Migrate

import Guide.Markdown
import Guide.Types.Hue
import Guide.Utils

import qualified Data.Aeson as A
import qualified Data.Set as S
import qualified Data.Text as T

----------------------------------------------------------------------------
-- General notes on code
----------------------------------------------------------------------------

{-

If you want to add a field to one of the types, see Note [extending types].

For an explanation of deriveSafeCopySorted, see Note [acid-state].

-}

----------------------------------------------------------------------------
-- Trait
----------------------------------------------------------------------------

-- | A trait (pro or con). Traits are stored in items.
data Trait = Trait {
  traitUid     :: Uid Trait,
  traitContent :: MarkdownInline }
  deriving (Show, Generic, Data)

deriveSafeCopySorted 4 'extension ''Trait
makeClassWithLenses ''Trait

changelog ''Trait (Current 4, Past 3) []
deriveSafeCopySorted 3 'base ''Trait_v3

instance A.ToJSON Trait where
  toJSON = A.genericToJSON A.defaultOptions {
    A.fieldLabelModifier = over _head toLower . drop (T.length "trait") }

-- | ADT for trait type. Traits can be pros (positive traits) and cons
-- (negative traits).
data TraitType = TraitTypePro | TraitTypeCon
  deriving (Eq, Show)

----------------------------------------------------------------------------
-- Item
----------------------------------------------------------------------------

-- | Kind of an item (items can be libraries, tools, etc).
data ItemKind
  = Library (Maybe Text)  -- Hackage name
  | Tool (Maybe Text)     -- Hackage name
  | Other
  deriving (Eq, Show, Generic, Data)

deriveSafeCopySimple 3 'extension ''ItemKind

hackageName :: Traversal' ItemKind (Maybe Text)
hackageName f (Library x) = Library <$> f x
hackageName f (Tool x)    = Tool <$> f x
hackageName _ Other       = pure Other

instance A.ToJSON ItemKind where
  toJSON (Library x) = A.object [
    "tag"      A..= ("Library" :: Text),
    "contents" A..= x ]
  toJSON (Tool x) = A.object [
    "tag"      A..= ("Tool" :: Text),
    "contents" A..= x ]
  toJSON Other = A.object [
    "tag"      A..= ("Other" :: Text) ]

instance A.FromJSON ItemKind where
  parseJSON = A.withObject "ItemKind" $ \o ->
      o A..: "tag" >>= \case
        ("Library" :: Text) -> Library <$> o A..: "contents"
        "Tool"    -> Tool <$> o A..: "contents"
        "Other"   -> pure Other
        tag       -> fail ("unknown tag " ++ show tag)

data ItemKind_v2
  = Library_v2 (Maybe Text)
  | Tool_v2 (Maybe Text)
  | Other_v2

-- TODO: at the next migration change this to deriveSafeCopySimple!
deriveSafeCopy 2 'base ''ItemKind_v2

instance Migrate ItemKind where
  type MigrateFrom ItemKind = ItemKind_v2
  migrate (Library_v2 x) = Library x
  migrate (Tool_v2 x)    = Tool x
  migrate Other_v2       = Other

-- | Different kinds of sections inside items. This type is only used for
-- 'categoryEnabledSections'.
data ItemSection
  = ItemProsConsSection
  | ItemEcosystemSection
  | ItemNotesSection
  deriving (Eq, Ord, Show, Generic, Data)

deriveSafeCopySimple 0 'base ''ItemSection

instance A.ToJSON ItemSection where
  toJSON = A.genericToJSON A.defaultOptions

instance A.FromJSON ItemSection where
  parseJSON = A.genericParseJSON A.defaultOptions

-- TODO: add a field like “people to ask on IRC about this library if you
-- need help”

-- | An item (usually a library). Items are stored in categories.
data Item = Item {
  itemUid         :: Uid Item,        -- ^ Item ID
  itemName        :: Text,            -- ^ Item title
  itemCreated     :: UTCTime,         -- ^ When the item was created
  itemHackage     :: Maybe Text,      -- ^ Package name on Hackage
  itemSummary     :: MarkdownBlock,   -- ^ Item summary
  itemPros        :: [Trait],         -- ^ Pros (positive traits)
  itemProsDeleted :: [Trait],         -- ^ Deleted pros go here (so that
                                      --   it'd be easy to restore them)
  itemCons        :: [Trait],         -- ^ Cons (negative traits)
  itemConsDeleted :: [Trait],         -- ^ Deleted cons go here
  itemEcosystem   :: MarkdownBlock,   -- ^ The ecosystem section
  itemNotes       :: MarkdownTree,    -- ^ The notes section
  itemLink        :: Maybe Url        -- ^ Link to homepage or something
  }
  deriving (Show, Generic, Data)

deriveSafeCopySorted 13 'extension ''Item
makeClassWithLenses ''Item

changelog ''Item (Current 13, Past 12)
  [Removed "itemGroup_"  [t|Maybe Text|] ]
deriveSafeCopySorted 12 'extension ''Item_v12

changelog ''Item (Past 12, Past 11)
  [Removed "itemKind"  [t|ItemKind|],
   Added "itemHackage" [hs|
     case itemKind of
       Library m -> m
       Tool m -> m
       Other -> Nothing |],
   Removed "itemDescription" [t|MarkdownBlock|],
   Added "itemSummary" [hs|
     itemDescription |] ]
deriveSafeCopySorted 11 'extension ''Item_v11

changelog ''Item (Past 11, Past 10) []
deriveSafeCopySorted 10 'base ''Item_v10

instance A.ToJSON Item where
  toJSON = A.genericToJSON A.defaultOptions {
    A.fieldLabelModifier = over _head toLower . drop (T.length "item") }

----------------------------------------------------------------------------
-- Category
----------------------------------------------------------------------------

-- | Category status
data CategoryStatus
  = CategoryStub                -- ^ “Stub” = just created
  | CategoryWIP                 -- ^ “WIP” = work in progress
  | CategoryFinished            -- ^ “Finished” = complete or nearly complete
  deriving (Eq, Show, Generic, Data)

deriveSafeCopySimple 2 'extension ''CategoryStatus

instance A.ToJSON CategoryStatus where
  toJSON = A.genericToJSON A.defaultOptions

instance A.FromJSON CategoryStatus where
  parseJSON = A.genericParseJSON A.defaultOptions

data CategoryStatus_v1
  = CategoryStub_v1
  | CategoryWIP_v1
  | CategoryMostlyDone_v1
  | CategoryFinished_v1

deriveSafeCopySimple 1 'base ''CategoryStatus_v1

instance Migrate CategoryStatus where
  type MigrateFrom CategoryStatus = CategoryStatus_v1
  migrate CategoryStub_v1       = CategoryStub
  migrate CategoryWIP_v1        = CategoryWIP
  migrate CategoryMostlyDone_v1 = CategoryFinished
  migrate CategoryFinished_v1   = CategoryFinished

-- | A category
data Category = Category {
  categoryUid             :: Uid Category,
  categoryTitle           :: Text,
  -- | When the category was created
  categoryCreated         :: UTCTime,
  -- | The “grandcategory” of the category (“meta”, “basics”, etc)
  categoryGroup           :: Text,
  categoryStatus          :: CategoryStatus,
  categoryNotes           :: MarkdownBlock,
  -- | Items stored in the category
  categoryItems           :: [Item],
  -- | Items that were deleted from the category. We keep them here to make
  -- it easier to restore them
  categoryItemsDeleted    :: [Item],
  -- | Enabled sections in this category. E.g, if this set contains
  -- 'ItemNotesSection', then notes will be shown for each item
  categoryEnabledSections :: Set ItemSection
  }
  deriving (Show, Generic, Data)

deriveSafeCopySorted 12 'extension ''Category
makeClassWithLenses ''Category

changelog ''Category (Current 12, Past 11)
  [Removed "categoryGroups" [t|Map Text Hue|] ]
deriveSafeCopySorted 11 'extension ''Category_v11

changelog ''Category (Past 11, Past 10)
  [Removed "categoryProsConsEnabled"  [t|Bool|],
   Removed "categoryEcosystemEnabled" [t|Bool|],
   Removed "categoryNotesEnabled"     [t|Bool|],
   Added   "categoryEnabledSections"  [hs|
     S.fromList $ concat
       [ [ItemProsConsSection  | categoryProsConsEnabled]
       , [ItemEcosystemSection | categoryEcosystemEnabled]
       , [ItemNotesSection     | categoryNotesEnabled] ] |] ]
deriveSafeCopySorted 10 'extension ''Category_v10

changelog ''Category (Past 10, Past 9)
  [Added "categoryNotesEnabled" [hs|True|]]
deriveSafeCopySorted 9 'extension ''Category_v9

changelog ''Category (Past 9, Past 8) []
deriveSafeCopySorted 8 'base ''Category_v8

instance A.ToJSON Category where
  toJSON = A.genericToJSON A.defaultOptions {
    A.fieldLabelModifier = over _head toLower . drop (T.length "category") }

-- | Category identifier (used in URLs). E.g. for a category with title
-- “Performance optimization” and UID “t3c9hwzo” the slug would be
-- @performance-optimization-t3c9hwzo@.
categorySlug :: Category -> Text
categorySlug category =
  format "{}-{}" (makeSlug (categoryTitle category)) (categoryUid category)
