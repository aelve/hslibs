{-# LANGUAGE OverloadedStrings #-}


-- | Encoders and decoders for types used in the database schema.
module Guide.Database.Convert
       (
       -- * 'Bool'
         boolParam
       , boolParamNullable
       , boolColumn
       , boolColumnNullable

       -- * 'Text'
       , textParam
       , textParamNullable
       , textColumn
       , textColumnNullable

       -- * 'Uid'
       , uidParam
       , uidColumn

       -- * ['Uid']
       , uidsParam
       , uidsColumn

       -- * 'UTCTime'
       , timestamptzParam
       , timestamptzColumn

       -- * 'TraitType'
       , traitTypeParam
       , traitTypeColumn

       -- * 'CategoryStatus'
       , categoryStatusParam
       , categoryStatusColumn

       -- * @Set 'ItemSection'@
       , itemSectionSetParam
       , itemSectionSetColumn

       -- * 'CategoryRow'
       , categoryRowParams
       , categoryRowColumns

       -- * 'ItemRow'
       , itemRowParams
       , itemRowColumns

       -- * 'TraitRow'
       , traitRowParams
       , traitRowColumns
       ) where


import Imports

import Data.Functor.Contravariant (contramap, (>$<))

import qualified Data.Set as Set
import qualified Hasql.Decoders as HD
import qualified Hasql.Encoders as HE

import Guide.Database.Types
import Guide.Types.Core (CategoryStatus (..), ItemSection (..), TraitType (..))
import Guide.Utils (Uid (..))


----------------------------------------------------------------------------
-- Bool
----------------------------------------------------------------------------

-- | Pass a 'Bool' to a query.
boolParam :: HE.Params Bool
boolParam = HE.param (HE.nonNullable HE.bool)

-- | Pass a nullable 'Bool' to a query.
boolParamNullable :: HE.Params (Maybe Bool)
boolParamNullable = HE.param (HE.nullable HE.bool)

-- | Get a 'Bool' from a query.
boolColumn :: HD.Row Bool
boolColumn = HD.column (HD.nonNullable HD.bool)

-- | Get a nullable 'Bool' from a query.
boolColumnNullable :: HD.Row Bool
boolColumnNullable = HD.column (HD.nonNullable HD.bool)

----------------------------------------------------------------------------
-- Text
----------------------------------------------------------------------------

-- | Pass a 'Text' to a query.
textParam :: HE.Params Text
textParam = HE.param (HE.nonNullable HE.text)

-- | Pass a nullable 'Text' to a query.
textParamNullable :: HE.Params (Maybe Text)
textParamNullable = HE.param (HE.nullable HE.text)

-- | Get a 'Text' from a query.
textColumn :: HD.Row Text
textColumn = HD.column (HD.nonNullable HD.text)

-- | Get a nullable 'Text' from a query.
textColumnNullable :: HD.Row (Maybe Text)
textColumnNullable = HD.column (HD.nullable HD.text)

----------------------------------------------------------------------------
-- Uid
----------------------------------------------------------------------------

-- | Encode a 'Uid'.
uidEncoder :: HE.Value (Uid a)
uidEncoder = contramap uidToText HE.text

-- | Pass a 'Uid' to a query.
uidParam :: HE.Params (Uid a)
uidParam = HE.param (HE.nonNullable uidEncoder)

-- | Decode a 'Uid'.
uidDecoder :: HD.Value (Uid a)
uidDecoder = Uid <$> HD.text

-- | Get a 'Uid' from a query.
uidColumn :: HD.Row (Uid a)
uidColumn = HD.column (HD.nonNullable uidDecoder)

----------------------------------------------------------------------------
-- UTCTime
----------------------------------------------------------------------------

-- | Pass a 'UTCTime' to a query.
timestamptzParam :: HE.Params UTCTime
timestamptzParam = HE.param (HE.nonNullable HE.timestamptz)

-- | Get a 'UTCTime' from a query.
timestamptzColumn :: HD.Row UTCTime
timestamptzColumn = HD.column (HD.nonNullable HD.timestamptz)

----------------------------------------------------------------------------
-- TraitType
----------------------------------------------------------------------------

-- | Encode a 'TraitType'.
traitTypeEncoder :: HE.Value TraitType
traitTypeEncoder = HE.enum $ \case
  TraitTypePro -> "pro"
  TraitTypeCon -> "con"

-- | Pass a 'TraitType' to a query.
traitTypeParam :: HE.Params TraitType
traitTypeParam = HE.param (HE.nonNullable traitTypeEncoder)

-- | Decode a 'TraitType'.
traitTypeDecoder :: HD.Value TraitType
traitTypeDecoder = HD.enum $ \case
  "pro" -> Just TraitTypePro
  "con" -> Just TraitTypeCon
  _ -> Nothing

-- | Get a 'TraitType' from a query.
traitTypeColumn :: HD.Row TraitType
traitTypeColumn = HD.column (HD.nonNullable traitTypeDecoder)

----------------------------------------------------------------------------
-- CategoryStatus
----------------------------------------------------------------------------

-- | Encode a 'CategoryStatus'.
categoryStatusEncoder :: HE.Value CategoryStatus
categoryStatusEncoder = HE.enum $ \case
  CategoryStub -> "stub"
  CategoryWIP -> "wip"
  CategoryFinished -> "finished"

-- | Pass a 'CategoryStatus' to a query.
categoryStatusParam :: HE.Params CategoryStatus
categoryStatusParam = HE.param (HE.nonNullable categoryStatusEncoder)

-- | Decode a 'CategoryStatus'.
categoryStatusDecoder :: HD.Value CategoryStatus
categoryStatusDecoder = HD.enum $ \case
  "stub" -> Just CategoryStub
  "wip" -> Just CategoryWIP
  "finished" -> Just CategoryFinished
  _ -> Nothing

-- | Get a 'CategoryStatus' from a query.
categoryStatusColumn :: HD.Row CategoryStatus
categoryStatusColumn = HD.column (HD.nonNullable categoryStatusDecoder)

----------------------------------------------------------------------------
-- Set ItemSection
----------------------------------------------------------------------------

-- | Encode an 'ItemSection'.
itemSectionEncoder :: HE.Value ItemSection
itemSectionEncoder = HE.enum $ \case
  ItemProsConsSection -> "pros_cons"
  ItemEcosystemSection -> "ecosystem"
  ItemNotesSection -> "notes"

-- | Pass a @Set ItemSection@ to a query.
itemSectionSetParam :: HE.Params (Set ItemSection)
itemSectionSetParam = contramap Set.toList
  $ HE.param
  $ HE.nonNullable
  $ HE.foldableArray
  $ HE.nonNullable
  $ itemSectionEncoder

-- | Decode an 'ItemSection'.
itemSectionDecoder :: HD.Value ItemSection
itemSectionDecoder = HD.enum $ \case
  "pros_cons" -> Just ItemProsConsSection
  "ecosystem" -> Just ItemEcosystemSection
  "notes" -> Just ItemNotesSection
  _ -> Nothing

-- | Get a @Set ItemSection@ from a query.
itemSectionSetColumn :: HD.Row (Set ItemSection)
itemSectionSetColumn =
  fmap Set.fromList
  $ HD.column
  $ HD.nonNullable
  $ HD.listArray
  $ HD.nonNullable
  $ itemSectionDecoder

----------------------------------------------------------------------------
-- [Uid]
----------------------------------------------------------------------------

-- | Encode a ['Uid'].
uidsEncoder :: HE.Value [Uid a]
uidsEncoder = HE.foldableArray $ HE.nonNullable uidEncoder

-- | Pass a ['Uid'] to a query.
uidsParam :: HE.Params [Uid a]
uidsParam = HE.param $ HE.nonNullable uidsEncoder

-- | Decode a ['Uid'].
uidsDecoder :: HD.Value [Uid a]
uidsDecoder = HD.listArray $ HD.nonNullable uidDecoder

-- | Get a ['Uid'] from a query.
uidsColumn :: HD.Row [Uid a]
uidsColumn = HD.column $ HD.nonNullable uidsDecoder

----------------------------------------------------------------------------
-- CategoryRow
----------------------------------------------------------------------------

-- | Pass a 'CategoryRow' to query.
categoryRowParams :: HE.Params CategoryRow
categoryRowParams
  =  (categoryRowUid >$< uidParam)
  <> (categoryRowTitle >$< textParam)
  <> (categoryRowCreated >$< timestamptzParam)
  <> (categoryRowGroup >$< textParam)
  <> (categoryRowStatus >$< categoryStatusParam)
  <> (categoryRowNotes >$< textParam)
  <> (categoryRowEnabledSections >$< itemSectionSetParam)
  <> (categoryRowItemsOrder >$< uidsParam)

-- | Get a 'CategoryRow' from query.
categoryRowColumns :: HD.Row CategoryRow
categoryRowColumns = do
  categoryRowUid <- uidColumn
  categoryRowTitle <- textColumn
  categoryRowCreated <- timestamptzColumn
  categoryRowGroup <- textColumn
  categoryRowStatus <- categoryStatusColumn
  categoryRowNotes <- textColumn
  categoryRowEnabledSections <- itemSectionSetColumn
  categoryRowItemsOrder <- uidsColumn
  pure CategoryRow{..}

----------------------------------------------------------------------------
-- ItemRow
----------------------------------------------------------------------------

-- | Pass a 'ItemRow' to query.
itemRowParams :: HE.Params ItemRow
itemRowParams
  =  (itemRowUid >$< uidParam)
  <> (itemRowName >$< textParam)
  <> (itemRowCreated >$< timestamptzParam)
  <> (itemRowLink >$< textParamNullable)
  <> (itemRowHackage >$< textParamNullable)
  <> (itemRowSummary >$< textParam)
  <> (itemRowEcosystem >$< textParam)
  <> (itemRowNotes >$< textParam)
  <> (itemRowDeleted >$< boolParam)
  <> (itemRowCategoryUid >$< uidParam)
  <> (itemRowProsOrder >$< uidsParam)
  <> (itemRowConsOrder >$< uidsParam)

-- | Get a 'ItemRow' from query.
itemRowColumns :: HD.Row ItemRow
itemRowColumns = do
  itemRowUid <- uidColumn
  itemRowName <- textColumn
  itemRowCreated <- timestamptzColumn
  itemRowLink <- textColumnNullable
  itemRowHackage <- textColumnNullable
  itemRowSummary <- textColumn
  itemRowEcosystem <- textColumn
  itemRowNotes <- textColumn
  itemRowDeleted <- boolColumn
  itemRowCategoryUid <- uidColumn
  itemRowProsOrder <- uidsColumn
  itemRowConsOrder <- uidsColumn
  pure ItemRow{..}

----------------------------------------------------------------------------
-- TraitRow
----------------------------------------------------------------------------

-- | Pass a 'TraitRow' to query.
traitRowParams :: HE.Params TraitRow
traitRowParams
  =  (traitRowUid >$< uidParam)
  <> (traitRowContent >$< textParam)
  <> (traitRowDeleted >$< boolParam)
  <> (traitRowType >$< traitTypeParam)
  <> (traitRowItemUid >$< uidParam)

-- | Get a 'TraitRow' from query.
traitRowColumns :: HD.Row TraitRow
traitRowColumns = do
  traitRowUid <- uidColumn
  traitRowContent <- textColumn
  traitRowDeleted <- boolColumn
  traitRowType <- traitTypeColumn
  traitRowItemUid <- uidColumn
  pure TraitRow{..}