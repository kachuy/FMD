unit Tsumino;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, WebsiteModules, uData, uBaseUnit, uDownloadsManager,
  XQueryEngineHTML, httpsendthread, synautil, RegExpr;

implementation

const
  //dirurl = '/Browse/Index/1/';
  // '/?pageNumber=532&RawSearch=&SortOptions=Newest&PageMinimum=1&PageMaximum=10000&RateMinimum=0&RateMaximum=5'
  dirurl = '/Browse/Query';
  dirurldata = 'pageNumber=';
  dirurldataend = '&RawSearch=&SortOptions=Newest&PageMinimum=1&PageMaximum=10000&RateMinimum=0&RateMaximum=5';

function GetDirectoryPageNumber(const MangaInfo: TMangaInformation;
  var Page: Integer; const Module: TModuleContainer): Integer;
begin
  Result := NET_PROBLEM;
  Page := 1;
  if MangaInfo = nil then Exit(UNKNOWN_ERROR);
  if MangaInfo.FHTTP.POST(Module.RootURL + dirurl, dirurldata + '1' + dirurldataend) then
  begin
    Result := NO_ERROR;
    Page := StrToIntDef(XPathString('json(*)("PageCount")', MangaInfo.FHTTP.Document), 1);
  end;
end;

function GetNameAndLink(const MangaInfo: TMangaInformation;
  const ANames, ALinks: TStringList; const AURL: String;
  const Module: TModuleContainer): Integer;
var
  v: IXQValue;
  s: String;
begin
  Result := NET_PROBLEM;
  if MangaInfo = nil then Exit(UNKNOWN_ERROR);
  if MangaInfo.FHTTP.POST(Module.RootURL + dirurl,
    dirurldata + IncStr(AURL) + dirurldataend) then
  begin
    Result := NO_ERROR;
    with TXQueryEngineHTML.Create(MangaInfo.FHTTP.Document) do
      try
        s := XPathString('json(*)("Data")');
        if s <> '' then
        begin
          ParseHTML(s);
          for v in XPath('//div[@class="overlay"]/a/@href') do
            ALinks.Add(v.toString);
          for v in XPath('//div[@class="overlay"]/div[@class="overlay-data"]/div[@class="overlay-title"]') do
            ANames.Add(v.toString);
        end;
      finally
        Free;
      end;
  end;
end;

function GetInfo(const MangaInfo: TMangaInformation;
  const AURL: String; const Module: TModuleContainer): Integer;
begin
  Result := NET_PROBLEM;
  if MangaInfo = nil then Exit(UNKNOWN_ERROR);
  with MangaInfo.FHTTP, MangaInfo.mangaInfo do begin
    url := FillHost(Module.RootURL, AURL);
    if GET(url) then begin
      Result := NO_ERROR;
      with TXQueryEngineHTML.Create(Document) do
        try
          coverLink := XPathString('//img[@class="book-page-image img-responsive"]/@src');
          if coverLink <> '' then coverLink := MaybeFillHost(Module.RootURL, coverLink);
          if title = '' then title := XPathString(
              '//div[@class="book-line"][starts-with(.,"Title")]/div[@class="book-data"]');
          artists := XPathString('//div[@class="book-line"][starts-with(.,"Artist")]/div[@class="book-data"]');
          genres := XPathStringAll(
            '//div[@class="book-line"][starts-with(.,"Parody") or starts-with(.,"Characters") or starts-with(.,"Tags")]/div[@class="book-data"]/*');
          if title <> '' then begin
            chapterLinks.Add(url);
            chapterName.Add(title);
          end;
        finally
          Free;
        end;
    end;
  end;
end;

function GetPageNumber(const DownloadThread: TDownloadThread;
  const AURL: String; const Module: TModuleContainer): Boolean;
var
  source: TStringList;
  i, pgLast: Integer;
  thumbUrl: String;
begin
  Result := False;
  if DownloadThread = nil then Exit;
  with DownloadThread.FHTTP, DownloadThread.Task.Container do begin
    PageLinks.Clear;
    PageNumber := 0;
    if GET(FillHost(Module.RootURL, AURL)) then begin
      Result := True;
      source := TStringList.Create;
      try
        source.LoadFromStream(Document);
        pgLast := 0;
        thumbUrl := '';
        if source.Count > 0 then
          for i := 0 to source.Count - 1 do begin
            if Pos('var pgLast', source[i]) > 0 then
              pgLast := StrToIntDef(GetValuesFromString(source[i], '='), 0)
            else if Pos('var thumbUrl', source[i]) > 0 then begin
              thumbUrl := GetValuesFromString(source[i], '=');
              Break;
            end;
          end;
        if (pgLast > 0) and (thumbUrl <> '') then begin
          thumbUrl := ReplaceRegExpr('(?i)/Thumb(/\d+/)[9]+', thumbUrl, '/Image$1', True);
          thumbUrl := AppendURLDelim(FillHost(Module.RootURL, thumbUrl));
          for i := 1 to pgLast do
            PageLinks.Add(thumbUrl + IntToStr(i));
        end;
      finally
        source.Free;
      end;
    end;
  end;
end;

procedure RegisterModule;
begin
  with AddModule do
  begin
    Website := 'Tsumino';
    RootURL := 'http://www.tsumino.com';
    OnGetDirectoryPageNumber := @GetDirectoryPageNumber;
    OnGetNameAndLink := @GetNameAndLink;
    OnGetInfo := @GetInfo;
    OnGetPageNumber := @GetPageNumber;
    SortedList := True;
  end;
end;

initialization
  RegisterModule;

end.
