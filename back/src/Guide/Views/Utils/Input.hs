{-# OPTIONS_GHC -fno-warn-name-shadowing #-}

-- | Lucid rendering for inputs and form fields.
module Guide.Views.Utils.Input
(
  inputText,
  inputTextArea,
  inputPassword,
  inputHidden,
  inputSelect,
  inputRadio,
  inputCheckbox,
  inputFile,
  inputSubmit,
  label,
  form,
  errorList,
  childErrorList,
  ifSingleton
)
where

import Imports hiding (for_)

import Lucid
import Text.Digestive.View

ifSingleton :: Bool -> a -> [a]
ifSingleton False _ = []
ifSingleton True  a = [a]

inputText :: Monad m => Text -> View v -> HtmlT m ()
inputText ref view = input_
    [ type_    "text"
    , id_      ref'
    , name_    ref'
    , value_ $ fieldInputText ref view
    ]
  where
    ref' = absoluteRef ref view


inputTextArea :: ( Monad m
                 ) => Maybe Int         -- ^ Rows
                   -> Maybe Int         -- ^ Columns
                   -> Text              -- ^ Form path
                   -> View (HtmlT m ()) -- ^ View
                   -> HtmlT m ()        -- ^ Resulting HTML
inputTextArea r c ref view = textarea_
    ([ id_     ref'
     , name_   ref'
     ] ++ rows' r ++ cols' c) $
        toHtmlRaw $ fieldInputText ref view
  where
    ref'          = absoluteRef ref view
    rows' (Just x) = [rows_ $ toText $ show x]
    rows' _        = []
    cols' (Just x) = [cols_ $ toText $ show x]
    cols' _        = []


inputPassword :: Monad m => Text -> View v -> HtmlT m ()
inputPassword ref view = input_
    [ type_    "password"
    , id_      ref'
    , name_    ref'
    , value_ $ fieldInputText ref view
    ]
  where
    ref' = absoluteRef ref view


inputHidden :: Monad m => Text -> View v -> HtmlT m ()
inputHidden ref view = input_
    [ type_    "hidden"
    , id_      ref'
    , name_    ref'
    , value_ $ fieldInputText ref view
    ]
  where
    ref' = absoluteRef ref view


inputSelect :: Monad m => Text -> View (HtmlT m ()) -> HtmlT m ()
inputSelect ref view = select_
    [ id_   ref'
    , name_ ref'
    ] $ forM_ choices $ \(i, c, sel) -> option_
          (value_ (value i) : ifSingleton sel (selected_ "selected")) c
  where
    ref'    = absoluteRef ref view
    value i = ref' `mappend` "." `mappend` i
    choices = fieldInputChoice ref view


inputRadio :: ( Monad m
              ) => Bool              -- ^ Add @br@ tags?
                -> Text              -- ^ Form path
                -> View (HtmlT m ()) -- ^ View
                -> HtmlT m ()        -- ^ Resulting HTML
inputRadio brs ref view = forM_ choices $ \(i, c, sel) -> do
    let val = value i
    input_ $ [type_ "radio", value_ val, id_ val, name_ ref']
               ++ ifSingleton sel checked_
    label_ [for_ val] c
    when brs (br_ [])
  where
    ref'    = absoluteRef ref view
    value i = ref' `mappend` "." `mappend` i
    choices = fieldInputChoice ref view


inputCheckbox :: Monad m => Text -> View (HtmlT m ()) -> HtmlT m ()
inputCheckbox ref view = input_ $
    [ type_ "checkbox"
    , id_   ref'
    , name_ ref'
    ] ++ ifSingleton selected checked_
  where
    ref'     = absoluteRef ref view
    selected = fieldInputBool ref view


inputFile :: Monad m => Text -> View (HtmlT m ()) -> HtmlT m ()
inputFile ref view = input_
    [ type_  "file"
    , id_    ref'
    , name_  ref'
    ]
  where
    ref'  = absoluteRef ref view


inputSubmit :: Monad m => Text -> HtmlT m ()
inputSubmit value = input_
    [ type_  "submit"
    , value_ value
    ]


label :: Monad m => Text -> View v -> HtmlT m () -> HtmlT m ()
label ref view = label_
    [ for_ ref'
    ]
  where
    ref' = absoluteRef ref view


form
  :: Monad m
  => View (HtmlT m ()) -> Text -> [Attribute] -> HtmlT m () -> HtmlT m ()
form view action attributes = form_ $
    [ method_  "POST"
    , enctype_ (toText $ show $ viewEncType view)
    , action_  action
    ]
    ++ attributes


errorList :: Monad m => Text -> View (HtmlT m ()) -> HtmlT m ()
errorList ref view = case errors ref view of
    []   -> mempty
    errs -> ul_ [class_ "digestive-functors-error-list"] $ forM_ errs $ \e ->
              li_ [class_ "digestive-functors-error"] e


childErrorList :: Monad m => Text -> View (HtmlT m ()) -> HtmlT m ()
childErrorList ref view = case childErrors ref view of
    []   -> mempty
    errs -> ul_ [class_ "digestive-functors-error-list"] $ forM_ errs $ \e ->
              li_ [class_ "digestive-functors-error"] e
