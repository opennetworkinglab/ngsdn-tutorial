package org.onosproject.ngsdn.tutorial;

import com.google.common.collect.Lists;
import org.onlab.packet.Ip6Address;

import java.util.Arrays;
import java.util.List;
import java.util.Optional;
import java.util.stream.Collectors;

import org.onlab.packet.IpAddress;
import org.onlab.packet.IpPrefix;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import static org.onlab.packet.IpAddress.INET6_BYTE_LENGTH;

public class Gsrv6Compres {
    private static final Logger log = LoggerFactory.getLogger(Gsrv6Compres.class);
    public static final int GSIDLEN16 = 16;
    public static final int GSIDLEN32 = 32;
    public static final int COC16_FLAVOR = 0x02;
    public static final int COC32_FLAVOR = 0x01;
    public static final int COC16_SI_LEN = 0x3;  /*3 bit used for SI*/
    public static final int COC32_SI_LEN = 0x4;  /*4 bit used for SI*/
    public static final int COC16_MAX_ELEMENT = 0x8;  /*G-SID container number for 16 bit*/
    public static final int COC32_MAX_ELEMENT = 0x4; /*G-SID container number for 32 bit*/


    public  List<Ip6Address> SingleSegmentCompress( List<Ip6Address> segmentList, int CommonPrefixLength, int GSIDLength, int ArgLength)
    {
        Ip6Address CommonPrefix= null;
        IpPrefix ipPrefixFirst = null;
        IpPrefix ipPrefixNext = null;
        Ip6Address AddrTemp = null;
        Ip6Address AddrCotainer = null;
        List<Ip6Address> SingleCompressSid = Lists.newArrayList();
        int ContainElement = 0;
        int PrefilBits = 0;
        int GSidBits = 0;
        int ArgBits = 0;
        byte[] AddrArry = null;

        log.info("CommonPrefixLength:{},GSIDLength:{},ArgLength:{}",CommonPrefixLength ,GSIDLength,ArgLength);
        log.info("single segment size:{} " ,segmentList.size());

        if ((0 >= CommonPrefixLength) ||(CommonPrefixLength%8 !=0)|| (0 > ArgLength) || ((GSIDLength != GSIDLEN16)&&(GSIDLength != GSIDLEN32)) )
        {
            throw new RuntimeException("CommonPrefixLength " + CommonPrefixLength + "GSIDLength" +GSIDLength +"ArgLength"+ArgLength +"in paraer error");
        }

        if (((GSIDLength == GSIDLEN16) && (ArgLength <COC16_SI_LEN ))
           ||((GSIDLength == GSIDLEN32) && (ArgLength <COC32_SI_LEN )))
        {
            throw new RuntimeException("ArgLength"+ArgLength +"in paraer error");
        }

        if ((CommonPrefixLength + GSIDLength + ArgLength) != 128)
        {
            throw new RuntimeException("total error CommonPrefixLength" + CommonPrefixLength + "GSIDLength" + GSIDLength + "ArgLength"+ ArgLength );
        }

        if (segmentList.size() <= 2 ) {
            SingleCompressSid.addAll(segmentList);
            return SingleCompressSid;
        }

        /*The first IP address can be modified to a compressed IP address*/
        PrefilBits = CommonPrefixLength/8;
        GSidBits = GSIDLength/8;
        ArgBits = ArgLength/8;
        AddrTemp = segmentList.get(0);
        AddrArry = AddrTemp.toOctets();
        log.info("AddrArry.Length:{}",AddrArry.length);
        if (GSIDLength == GSIDLEN32)
        {
            AddrArry[AddrArry.length-1] |= (byte)0x03;
            AddrArry[AddrArry.length-1-ArgBits]|= (byte)COC32_FLAVOR;
            AddrArry[PrefilBits+GSidBits-1]|= (byte)COC32_FLAVOR;
        }
        else
        {
            AddrArry[AddrArry.length-1] |= (byte)0x07;
            AddrArry[AddrArry.length-1-ArgBits]|= (byte)COC16_FLAVOR;
            AddrArry[PrefilBits+GSidBits-1]|= (byte)COC16_FLAVOR;
        }
        AddrCotainer =Ip6Address.valueOf(AddrArry);
        SingleCompressSid.add(AddrCotainer);

        /*Check whether the compression condition with the same prefix and all Arg bits is 0*/
        ipPrefixFirst = IpPrefix.valueOf(AddrTemp,CommonPrefixLength);
        ContainElement = 0;
        AddrArry =new byte[INET6_BYTE_LENGTH];
        for (int sidIndex =1; sidIndex<segmentList.size(); sidIndex++)
        {
            AddrTemp = segmentList.get(sidIndex);
            byte[] TmpAddrArry = AddrTemp.toOctets();
            ipPrefixNext = IpPrefix.valueOf(AddrTemp,CommonPrefixLength);
            if (!ipPrefixNext.equals(ipPrefixFirst))
            {
                throw new RuntimeException("prefix not equal");
            }
            if (GSIDLength == GSIDLEN32)
            {
                for (int gsidIndex = 0; gsidIndex < GSidBits; gsidIndex++)
                {
                    AddrArry[ContainElement*GSidBits+gsidIndex]=  TmpAddrArry[PrefilBits+gsidIndex];
                }
                ContainElement++;
                if (sidIndex != segmentList.size()-1)
                {
                    AddrArry[ContainElement * GSidBits - 1] |= (byte) COC32_FLAVOR;
                }
                if ((ContainElement>=COC32_MAX_ELEMENT )||(sidIndex == segmentList.size()-1))
                {
                    AddrCotainer =Ip6Address.valueOf(AddrArry);
                    SingleCompressSid.add(AddrCotainer);
                    AddrArry = new byte[INET6_BYTE_LENGTH];
                    ContainElement =0;

                }
            }
            else
            {
                for (int gsidIndex = 0; gsidIndex < GSidBits; gsidIndex++)
                {
                    AddrArry[ContainElement*GSidBits+gsidIndex]=  TmpAddrArry[PrefilBits+gsidIndex];
                }
                ContainElement++;
                if (sidIndex != segmentList.size()-1)
                {
                    AddrArry[ContainElement * GSidBits - 1] |= (byte) COC16_FLAVOR;
                }
                if ((ContainElement>=COC16_MAX_ELEMENT )||(sidIndex == segmentList.size()-1))
                {
                    AddrCotainer =Ip6Address.valueOf(AddrArry);
                    SingleCompressSid.add(AddrCotainer);
                    ContainElement =0;
                    AddrArry = new byte[INET6_BYTE_LENGTH];
                }
            }
        }
        log.info("SingleCompressSid length:{}",SingleCompressSid.size());
        return SingleCompressSid;
    }

    public Ip6Address AddrToSid( Ip6Address NodeAddr)
    {
        Ip6Address NodeSid =Ip6Address.valueOf(NodeAddr.toOctets());
        return NodeSid;
    }

    public boolean NodeGSrv6Ability( Ip6Address NodeAddr)
    {
        return true;
    }

    public int CompressPerfixLenGet( Ip6Address NodeAddr)
    {
        int CommonPrefixLength =64;
        return CommonPrefixLength;
    }

    public int CompressGsidLenGet( Ip6Address NodeAddr)
    {
        int GSIDLength =32;
        return GSIDLength;
    }

    public int CompressArgLenGet( Ip6Address NodeAddr)
    {
        int ArgLength =32;
        return ArgLength;
    }

    public boolean GsidPerfixMatch( Ip6Address GsidFirst,Ip6Address GsidNext,int CommonPrefixLength)
    {
        IpPrefix ipPrefixFirst = null;
        IpPrefix ipPrefixNext = null;

        ipPrefixFirst = IpPrefix.valueOf(GsidFirst,CommonPrefixLength);
        ipPrefixNext = IpPrefix.valueOf(GsidNext,CommonPrefixLength);
        if (ipPrefixFirst.equals(ipPrefixNext))
        {
            return true;
        }
        else
        {
            return false;
        }
    }

    public List<Ip6Address> GSrv6Compress( List<Ip6Address> SegmentList,boolean IsSid)
    {
        List<Ip6Address> SidListSrc =null;
        List<Ip6Address> GSidList = Lists.newArrayList();
        List<Ip6Address> SingleSegment =null;
        List<Ip6Address> SingleCompressSegment =null;
        Ip6Address CompressSidStart =null;
        Ip6Address CompressSidNext =null;
        int CommonPrefixLength =0;
        int GSIDLength=0;
        int ArgLength=0;
        int Index =0;

        /*Unified conversion to Sid information that needs to be compressed*/
        if (IsSid)
        {
            SidListSrc = SegmentList;
        }
        else
        {
            SidListSrc = Lists.newArrayList();
            for (int i=0;i<SegmentList.size();i++)
            {
                SidListSrc.add(AddrToSid(SegmentList.get(i)));
            }
        }
        /*Constructing compressible segments and compressing*/
        Index =0;
        log.info("souce of segment list:{} " ,SidListSrc.size());

        while (Index < SidListSrc.size())
        {
            SingleSegment = Lists.newArrayList();
            CompressSidStart = SegmentList.get(Index);
            CommonPrefixLength = CompressPerfixLenGet(CompressSidStart);
            GSIDLength = CompressGsidLenGet(CompressSidStart);
            ArgLength = CompressArgLenGet(CompressSidStart);

            log.info("first prefix compress begin Index:{}",Index);

            for (int i=Index; i<SidListSrc.size(); i++)
            {
                log.info("next prefix compress begin Index:{}",i);
                CompressSidNext = SegmentList.get(i);
                /*The nodes are incompressible, and they are pressed directly into the compression results without any processing*/
                if (!NodeGSrv6Ability(CompressSidNext))
                {
                    SingleCompressSegment = SingleSegmentCompress( SingleSegment,CommonPrefixLength, GSIDLength, ArgLength);
                    GSidList.addAll(SingleCompressSegment);
                    GSidList.add(CompressSidNext);
                    Index =i+1;
                    break;
                }
                /*Find the prefix matching, put it into the same compression segment for compression,
                find the first mismatched and start compression directly*/
                if(GsidPerfixMatch(CompressSidStart,CompressSidNext,CommonPrefixLength))
                {
                    SingleSegment.add(AddrToSid(CompressSidNext));
                    if (i == SidListSrc.size()-1)
                    {
                        SingleCompressSegment = SingleSegmentCompress( SingleSegment, CommonPrefixLength, GSIDLength, ArgLength);
                        log.info("SingleCompress size: {}",SingleCompressSegment.size());
                        GSidList.addAll(SingleCompressSegment);
                        Index =SidListSrc.size();
                        break;
                    }
                }
                else
                {
                    log.info("prefix mismatch");
                    SingleCompressSegment = SingleSegmentCompress( SingleSegment, CommonPrefixLength, GSIDLength, ArgLength);
                    log.info("SingleCompressed size: {}",SingleCompressSegment.size());
                    GSidList.addAll(SingleCompressSegment);
                    Index =i;
                    break;
                }
            }
        }
        log.info("gsrv6 size::{}",GSidList.size());
        return GSidList;
    }
}
